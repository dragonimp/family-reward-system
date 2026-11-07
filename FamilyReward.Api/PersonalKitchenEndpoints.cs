using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;

internal sealed record KitchenActor(string Owner, string Username);
internal static class PersonalKitchenEndpoints
{
    static string S(JsonObject o,string k) => o[k]?.ToString().Trim() ?? "";
    static Guid? Id(JsonObject o,string k) => Guid.TryParse(S(o,k),out var g)&&g!=Guid.Empty?g:null;
    static IResult Bad(string m) => Results.BadRequest(new {error=m});
    static IResult Missing() => Results.NotFound(new {error="内容不存在或无权访问。"});
    static string Hash(string s) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s))).ToLowerInvariant();
    internal static bool ValidDraft(JsonObject o) => S(o,"name").Length is >0 and <=120
        && o["ingredients"] is JsonArray {Count:>0 and <=80} ingredients && ingredients.All(i=>i is JsonObject x && S(x,"name").Length is >0 and <=120 && S(x,"quantity").Length<=100 && S(x,"unit").Length<=30)
        && o["steps"] is JsonArray {Count:>0 and <=64} steps && steps.Select((s,i)=>s is JsonObject x && S(x,"instruction").Length is >0 and <=3000 && int.TryParse(S(x,"number"),out var n) && n==i+1).All(v=>v)
        && o.ToJsonString().Length<=100000;
    internal static bool Jpeg(byte[] b)
    {
        if(b.Length is <20 or >8388608 || b[0]!=255 || b[1]!=216 || b[^2]!=255 || b[^1]!=217)return false;
        for(int p=2;p+8<b.Length;){if(b[p++]!=255)return false;while(p<b.Length&&b[p]==255)p++;if(p>=b.Length)return false;int marker=b[p++];if(marker==218)break;if(marker is 216 or 217)continue;if(p+1>=b.Length)return false;int n=b[p]*256+b[p+1];if(n<2||p+n>b.Length)return false;
            if(marker is 192 or 193 or 194){int h=b[p+3]*256+b[p+4],w=b[p+5]*256+b[p+6];return w>0&&h>0&&(long)w*h<=24000000; }p+=n;}
        return false;
    }
    static async Task<NpgsqlConnection> Open(string cs){var c=new NpgsqlConnection(cs);await c.OpenAsync();return c;}
    internal static async Task<JsonObject?> Row(NpgsqlConnection c,string sql,params (string,object)[] args)
    {await using var q=new NpgsqlCommand(sql,c);foreach(var (k,v) in args)q.Parameters.AddWithValue(k,v);var text=await q.ExecuteScalarAsync();return text is string s?JsonNode.Parse(s) as JsonObject:null;}
    static async Task<int> Exec(NpgsqlConnection c,string sql,params (string,object)[] args)
    {await using var q=new NpgsqlCommand(sql,c);foreach(var(k,v) in args)q.Parameters.AddWithValue(k,v);return await q.ExecuteNonQueryAsync();}
    internal static Task<JsonObject?> Recipe(NpgsqlConnection c,string owner,Guid id,string kind,bool deleted=false) => Row(c,kind=="public"?
        "SELECT body::text FROM kitchen_recipes WHERE id=@id AND published":
        "SELECT body::text FROM kitchen_personal_recipes WHERE id=@id AND owner_id=@owner"+(deleted?"":" AND deleted_at IS NULL"),("id",id),("owner",owner));
    const string ListSql="""
        WITH candidates AS (
          SELECT p.id,'private' AS kind,p.body,p.version,p.original_media_id,p.recognition_id,p.source_text,p.ai_result,p.updated_at FROM kitchen_personal_recipes p WHERE p.owner_id=@owner AND p.deleted_at IS NULL
          UNION ALL
          SELECT p.id,'public',p.body,p.version,NULL::uuid,NULL::uuid,''::text,NULL::jsonb,now() FROM kitchen_recipes p WHERE p.published AND
            (EXISTS(SELECT 1 FROM kitchen_user_recipes l WHERE l.owner_id=@owner AND l.recipe_id=p.id AND (l.favorite OR l.starred)) OR EXISTS(SELECT 1 FROM kitchen_cooking_checkins h WHERE h.owner_id=@owner AND h.recipe_id=p.id AND h.deleted_at IS NULL))
        ) SELECT jsonb_build_object('items',COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.starred DESC,x.name),'[]'::jsonb))::text FROM (
          SELECT c.id,c.kind,c.body AS recipe,c.body->>'name' AS name,c.version,c.original_media_id AS "originalMediaId",c.recognition_id AS "recognitionId",c.source_text AS "sourceText",c.ai_result AS "aiResult",
            COALESCE(l.favorite,false) AS favorite,COALESCE(l.starred,false) AS starred,
            (SELECT count(*) FROM kitchen_cooking_checkins h WHERE h.owner_id=@owner AND h.recipe_id=c.id AND h.deleted_at IS NULL) AS "madeCount"
          FROM candidates c LEFT JOIN kitchen_user_recipes l ON l.owner_id=@owner AND l.recipe_id=c.id
          WHERE (@filter<>'uploaded' OR c.kind='private') AND (@filter<>'starred' OR l.starred) AND (@q='' OR strpos(lower(c.body->>'name'),lower(@q))>0)
          ORDER BY COALESCE(l.starred,false) DESC,c.updated_at DESC LIMIT 300
        ) x
        """;
    public static void MapPersonalKitchen(this WebApplication app,string cs,Func<HttpRequest,KitchenActor?> actor)
    {
        var group=app.MapGroup("/api/kitchen").RequireAuthorization().WithMetadata(new Microsoft.AspNetCore.Mvc.RequestSizeLimitAttribute(12*1024*1024));
        group.AddEndpointFilter(async (context,next)=>{if(actor(context.HttpContext.Request)==null)return Results.Unauthorized();context.HttpContext.Response.Headers.CacheControl="private, no-store";return await next(context);});
        group.MapGet("/catalog",async(HttpRequest r)=>{await using var c=await Open(cs);return Results.Json(await Row(c,"SELECT jsonb_build_object('items',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb))::text FROM (SELECT id,'public' AS kind,body->>'name' AS name FROM kitchen_recipes WHERE published UNION ALL SELECT id,'private',body->>'name' FROM kitchen_personal_recipes WHERE owner_id=@owner AND deleted_at IS NULL ORDER BY name LIMIT 500) x",("owner",actor(r)!.Owner)));});
        group.MapGet("/recipes",async(HttpRequest r)=>{var a=actor(r)!;await using var c=await Open(cs);return Results.Json(await Row(c,ListSql,("owner",a.Owner),("filter",r.Query["filter"].ToString()),("q",r.Query["q"].ToString().Trim().Length>120?"":r.Query["q"].ToString().Trim())));});
        group.MapGet("/recipes/{id:guid}",async(Guid id,HttpRequest r)=>{var a=actor(r)!;var kind=r.Query["kind"]=="private"?"private":"public";await using var c=await Open(cs);var body=await Recipe(c,a.Owner,id,kind);if(body==null)return Missing();
            var meta=await Row(c,"SELECT jsonb_build_object('favorite',COALESCE((SELECT favorite FROM kitchen_user_recipes WHERE owner_id=@owner AND recipe_id=@id),false),'starred',COALESCE((SELECT starred FROM kitchen_user_recipes WHERE owner_id=@owner AND recipe_id=@id),false),'madeCount',(SELECT count(*) FROM kitchen_cooking_checkins WHERE owner_id=@owner AND recipe_id=@id AND deleted_at IS NULL),'version',COALESCE((SELECT version FROM kitchen_personal_recipes WHERE owner_id=@owner AND id=@id),1))::text",("owner",a.Owner),("id",id));if(kind=="private"){var extra=await Row(c,"SELECT jsonb_build_object('originalMediaId',original_media_id,'recognitionId',recognition_id,'sourceText',source_text,'aiResult',ai_result)::text FROM kitchen_personal_recipes WHERE id=@id AND owner_id=@owner",("id",id),("owner",a.Owner));foreach(var pair in extra!)meta![pair.Key]=pair.Value?.DeepClone();}meta!["recipe"]=body;return Results.Json(meta);});
        group.MapPut("/recipes/{id:guid}",async(Guid id,JsonObject input,HttpRequest r)=>{
            var a=actor(r)!;if(id==Guid.Empty||input["recipe"] is not JsonObject draft||!ValidDraft(draft)||S(input,"confirmed")!="true")return Bad("请核对菜名、食材和有序步骤并确认保存。未知用量可留空。");
            var version=int.TryParse(S(input,"version"),out var expected)?expected:0;var media=Id(input,"originalMediaId");var recognition=Id(input,"recognitionId");await using var c=await Open(cs);await using var tx=await c.BeginTransactionAsync();await Exec(c,"SELECT pg_advisory_xact_lock(hashtext(@key))",("key",id.ToString("D")));
            if(media!=null&&await Row(c,"SELECT jsonb_build_object('id',id)::text FROM kitchen_personal_media WHERE id=@id AND owner_id=@owner AND purpose='recipe'",("id",media.Value),("owner",a.Owner))==null)return Missing();
            JsonObject? ai=null;if(recognition!=null){ai=await Row(c,"SELECT result::text FROM kitchen_recognition_tasks WHERE id=@id AND owner_id=@owner AND state='completed' AND media_id=@media",("id",recognition.Value),("owner",a.Owner),("media",(object?)media??DBNull.Value));if(ai==null)return Missing();}
            draft["recipeId"]=id.ToString("D");var source=S(input,"sourceText");if(source.Length>2000)return Bad("来源说明过长。");
            if(await Row(c,"SELECT jsonb_build_object('id',id)::text FROM kitchen_recipes WHERE id=@id",("id",id))!=null)return Results.Conflict(new{error="菜谱标识已存在，请重新创建。"});
            var existing=await Row(c,"SELECT jsonb_build_object('owner',owner_id,'version',version,'body',body,'deleted',deleted_at IS NOT NULL)::text FROM kitchen_personal_recipes WHERE id=@id FOR UPDATE",("id",id));
            if(existing!=null){if(S(existing,"owner")!=a.Owner||existing["deleted"]!.GetValue<bool>())return Missing();if(existing["version"]!.GetValue<int>()!=version){if(JsonNode.DeepEquals(existing["body"],draft))return Results.Ok(new{id,version=existing["version"]});return Results.Conflict(new{error="菜谱已变化，请重新打开后编辑。"});}
                await Exec(c,"UPDATE kitchen_personal_recipes SET body=@body::jsonb,original_media_id=@media,recognition_id=@recognition,ai_result=@ai::jsonb,source_text=@source,version=version+1,updated_at=now() WHERE id=@id AND owner_id=@owner",("body",draft.ToJsonString()),("media",(object?)media??DBNull.Value),("recognition",(object?)recognition??DBNull.Value),("ai",(object?)ai?.ToJsonString()??DBNull.Value),("source",source),("id",id),("owner",a.Owner));version++;
            }else{if(version!=0)return Missing();await Exec(c,"INSERT INTO kitchen_personal_recipes(id,owner_id,body,original_media_id,recognition_id,source_text,ai_result) VALUES(@id,@owner,@body::jsonb,@media,@recognition,@source,@ai::jsonb)",("id",id),("owner",a.Owner),("body",draft.ToJsonString()),("media",(object?)media??DBNull.Value),("recognition",(object?)recognition??DBNull.Value),("source",source),("ai",(object?)ai?.ToJsonString()??DBNull.Value));version=1;}
            await tx.CommitAsync();return Results.Ok(new{id,version});
        });
        group.MapDelete("/recipes/{id:guid}",async(Guid id,HttpRequest r)=>{await using var c=await Open(cs);var n=await Exec(c,"UPDATE kitchen_personal_recipes SET deleted_at=COALESCE(deleted_at,now()),updated_at=now() WHERE id=@id AND owner_id=@owner",("id",id),("owner",actor(r)!.Owner));return n==0?Missing():Results.Ok();});
        group.MapPut("/recipes/{id:guid}/relationship",async(Guid id,JsonObject b,HttpRequest r)=>{var a=actor(r)!;var kind=S(b,"kind");if(kind is not("private" or "public"))return Bad("菜谱类型无效。");await using var c=await Open(cs);if(await Recipe(c,a.Owner,id,kind)==null)return Missing();
            await Exec(c,"INSERT INTO kitchen_user_recipes(owner_id,recipe_id,kind,favorite,starred) VALUES(@owner,@id,@kind,@favorite,@starred) ON CONFLICT(owner_id,recipe_id) DO UPDATE SET favorite=EXCLUDED.favorite,starred=EXCLUDED.starred,updated_at=now()",("owner",a.Owner),("id",id),("kind",kind),("favorite",S(b,"favorite")=="true"),("starred",S(b,"starred")=="true"));return Results.Ok();});
        group.MapPost("/media",async(JsonObject b,HttpRequest r)=>{var a=actor(r)!;var id=Id(b,"id");var purpose=S(b,"purpose");byte[] bytes;try{var text=S(b,"base64");if(text.Length>11200000)return Bad("图片过大，请选择8MB以内的图片。");bytes=Convert.FromBase64String(text);}catch{return Bad("图片编码无效。");}if(id==null||purpose is not("recipe" or "checkin")||!Jpeg(bytes))return Bad("请上传有效JPEG图片，最大8MB、2400万像素。");
            await using var c=await Open(cs);var hash=Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();await using var tx=await c.BeginTransactionAsync();await Exec(c,"SELECT pg_advisory_xact_lock(hashtext(@owner))",("owner",a.Owner));
            var old=await Row(c,"SELECT jsonb_build_object('owner',owner_id,'sha',sha256,'purpose',purpose)::text FROM kitchen_personal_media WHERE id=@id",("id",id.Value));if(old!=null)return S(old,"owner")==a.Owner&&S(old,"sha")==hash&&S(old,"purpose")==purpose?Results.Ok(new{id}):Results.Conflict(new{error="图片请求冲突。"});
            var quota=await Row(c,"SELECT jsonb_build_object('n',COALESCE(sum(octet_length(content)),0))::text FROM kitchen_personal_media WHERE owner_id=@owner",("owner",a.Owner));if(quota!["n"]!.GetValue<long>()+bytes.Length>200*1024*1024)return Bad("个人厨房图片已达到200MB上限。");
            await Exec(c,"INSERT INTO kitchen_personal_media(id,owner_id,purpose,mime,content,sha256) VALUES(@id,@owner,@purpose,'image/jpeg',@bytes,@hash)",("id",id.Value),("owner",a.Owner),("purpose",purpose),("bytes",bytes),("hash",hash));await tx.CommitAsync();return Results.Ok(new{id});
        }).RequireRateLimiting("kitchen-upload");
        group.MapGet("/media/{id:guid}",async(Guid id,HttpRequest r)=>{await using var c=await Open(cs);await using var q=new NpgsqlCommand("SELECT content FROM kitchen_personal_media WHERE id=@id AND owner_id=@owner",c);q.Parameters.AddWithValue("id",id);q.Parameters.AddWithValue("owner",actor(r)!.Owner);return await q.ExecuteScalarAsync() is byte[] bytes?Results.File(bytes,"image/jpeg"):Missing();});
        group.MapGet("/checkins",async(HttpRequest r)=>{await using var c=await Open(cs);return Results.Json(await Row(c,"SELECT jsonb_build_object('items',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb))::text FROM (SELECT id,recipe_id AS \"recipeId\",kind,cooked_on AS \"cookedOn\",media_id AS \"mediaId\",note,recipe_name AS name,created_at AS \"createdAt\" FROM kitchen_cooking_checkins WHERE owner_id=@owner AND deleted_at IS NULL ORDER BY cooked_on DESC,created_at DESC LIMIT 500) x",("owner",actor(r)!.Owner)));});
        group.MapGet("/cooked",async(HttpRequest r)=>{await using var c=await Open(cs);return Results.Json(await Row(c,"SELECT jsonb_build_object('items',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb))::text FROM (SELECT recipe_id AS \"recipeId\",kind,max(recipe_name) AS name,count(*) AS \"madeCount\",max(cooked_on) AS \"lastCookedOn\" FROM kitchen_cooking_checkins WHERE owner_id=@owner AND deleted_at IS NULL AND recipe_id IS NOT NULL GROUP BY recipe_id,kind ORDER BY max(cooked_on) DESC) x",("owner",actor(r)!.Owner)));});
        group.MapPut("/checkins/{id:guid}",async(Guid id,JsonObject b,HttpRequest r)=>{
            var a=actor(r)!;var recipe=Id(b,"recipeId");var media=Id(b,"mediaId");var kind=S(b,"kind");if(id==Guid.Empty||media==null||recipe==null||kind is not("public" or "private")||!DateOnly.TryParseExact(S(b,"cookedOn"),"yyyy-MM-dd",CultureInfo.InvariantCulture,DateTimeStyles.None,out var day)||S(b,"note").Length>2000)return Bad("请选择菜谱、制作日期和成品照片。");
            await using var c=await Open(cs);await using var tx=await c.BeginTransactionAsync();var body=await Recipe(c,a.Owner,recipe.Value,kind);if(body==null||await Row(c,"SELECT jsonb_build_object('id',id)::text FROM kitchen_personal_media WHERE id=@id AND owner_id=@owner AND purpose='checkin'",("id",media.Value),("owner",a.Owner))==null)return Missing();
            var hash=Hash($"{recipe:D}|{kind}|{day:yyyy-MM-dd}|{media:D}|{S(b,"note")}");
            await Exec(c,"INSERT INTO kitchen_cooking_checkins(id,owner_id,recipe_id,kind,cooked_on,media_id,note,recipe_name,request_hash) VALUES(@id,@owner,@recipe,@kind,@day,@media,@note,@name,@hash) ON CONFLICT(id) DO NOTHING",("id",id),("owner",a.Owner),("recipe",recipe.Value),("kind",kind),("day",day),("media",media.Value),("note",S(b,"note")),("name",S(body,"name")),("hash",hash));
            var old=await Row(c,"SELECT jsonb_build_object('owner',owner_id,'hash',request_hash,'deleted',deleted_at IS NOT NULL)::text FROM kitchen_cooking_checkins WHERE id=@id",("id",id));if(S(old!,"owner")!=a.Owner)return Missing();if(S(old!,"hash")!=hash||old!["deleted"]!.GetValue<bool>())return Results.Conflict(new{error="同一打卡请求不能修改内容或重复恢复。"});await tx.CommitAsync();return Results.Ok(new{id});
        });
        group.MapPatch("/checkins/{id:guid}/recipe",async(Guid id,JsonObject b,HttpRequest r)=>{var a=actor(r)!;var recipe=Id(b,"recipeId");var kind=S(b,"kind");if(recipe==null||kind is not("public" or "private"))return Bad("请选择关联菜谱。");await using var c=await Open(cs);var body=await Recipe(c,a.Owner,recipe.Value,kind);if(body==null)return Missing();var n=await Exec(c,"UPDATE kitchen_cooking_checkins SET recipe_id=@recipe,kind=@kind,recipe_name=@name WHERE id=@id AND owner_id=@owner AND deleted_at IS NULL",("recipe",recipe.Value),("kind",kind),("name",S(body,"name")),("id",id),("owner",a.Owner));return n>0?Results.Ok():Missing();});
        group.MapDelete("/checkins/{id:guid}",async(Guid id,HttpRequest r)=>{await using var c=await Open(cs);var n=await Exec(c,"UPDATE kitchen_cooking_checkins SET deleted_at=COALESCE(deleted_at,now()) WHERE id=@id AND owner_id=@owner",("id",id),("owner",actor(r)!.Owner));return n>0?Results.Ok():Missing();});
        group.MapPost("/recognitions",async(JsonObject b,HttpRequest r)=>{var a=actor(r)!;var id=Id(b,"id");var media=Id(b,"mediaId");if(id==null||media==null)return Bad("请选择要识别的菜谱图片。");await using var c=await Open(cs);await using var tx=await c.BeginTransactionAsync();await Exec(c,"SELECT pg_advisory_xact_lock(hashtext(@owner))",("owner",a.Owner));
            if(await Row(c,"SELECT jsonb_build_object('id',id)::text FROM kitchen_personal_media WHERE id=@id AND owner_id=@owner AND purpose='recipe'",("id",media.Value),("owner",a.Owner))==null)return Missing();
            var old=await Row(c,"SELECT jsonb_build_object('owner',owner_id,'media',media_id)::text FROM kitchen_recognition_tasks WHERE id=@id",("id",id.Value));if(old!=null)return S(old,"owner")==a.Owner&&Guid.TryParse(S(old,"media"),out var previous)&&previous==media.Value?Results.Ok(new{id}):Results.Conflict();
            var quota=await Row(c,"SELECT jsonb_build_object('n',count(*))::text FROM kitchen_recognition_tasks WHERE owner_id=@owner AND created_at>now()-interval '1 day'",("owner",a.Owner));if(quota!["n"]!.GetValue<int>()>=10)return Results.Json(new{error="每天最多识别10次，可使用手动创建。"},statusCode:429);
            await Exec(c,"INSERT INTO kitchen_recognition_tasks(id,owner_id,username,media_id) VALUES(@id,@owner,@username,@media)",("id",id.Value),("owner",a.Owner),("username",a.Username),("media",media.Value));await tx.CommitAsync();return Results.Accepted(value:new{id});
        }).RequireRateLimiting("kitchen-upload");
        group.MapGet("/recognitions",async(HttpRequest r)=>{await using var c=await Open(cs);return Results.Json(await Row(c,"SELECT jsonb_build_object('items',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb))::text FROM (SELECT id,media_id AS \"mediaId\",state,result,error,created_at AS \"createdAt\" FROM kitchen_recognition_tasks WHERE owner_id=@owner ORDER BY created_at DESC LIMIT 20) x",("owner",actor(r)!.Owner)));});
        group.MapGet("/recognitions/{id:guid}",async(Guid id,HttpRequest r)=>{await using var c=await Open(cs);var row=await Row(c,"SELECT jsonb_build_object('id',id,'mediaId',media_id,'state',state,'result',result,'error',error)::text FROM kitchen_recognition_tasks WHERE id=@id AND owner_id=@owner",("id",id),("owner",actor(r)!.Owner));return row==null?Missing():Results.Json(row);});
    }
}
