using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using LinkoFamily;
using Npgsql;
using Microsoft.AspNetCore.Mvc;

internal static class DiningAccountEndpoints
{
    static async Task<JsonObject> Read(NpgsqlConnection c,string owner,NpgsqlTransaction? tx=null)
    {
        await using var q=new NpgsqlCommand("SELECT jsonb_build_object('archive',archive,'version',version,'updatedAt',updated_at)::text FROM account_dining_archives WHERE owner_id=@owner",c,tx);q.Parameters.AddWithValue("owner",owner);
        return await q.ExecuteScalarAsync() is string text?JsonNode.Parse(text)!.AsObject():new JsonObject{["archive"]=DiningSyncMerge.Empty(),["version"]=0};
    }
    public static void MapDiningAccounts(this WebApplication app,string cs,Func<HttpRequest,string?> ownerFor)
    {
        var group=app.MapGroup("/api/dining/account").RequireAuthorization();
        group.AddEndpointFilter(async(context,next)=>{
            if(ownerFor(context.HttpContext.Request) is null)return Results.Unauthorized();
            context.HttpContext.Response.Headers.CacheControl="private, no-store";
            try{return await next(context);}catch(DiningSyncConflictException e){return Results.Conflict(new{error=e.Message});}catch(Exception e) when(e is ArgumentException or InvalidOperationException or FormatException or OverflowException){return Results.BadRequest(new{error="干饭同步数据无效，请保留本机记录后重试。"});}
        });
        group.MapGet("",async(HttpRequest request)=>{await using var c=new NpgsqlConnection(cs);await c.OpenAsync();return Results.Json(await Read(c,ownerFor(request)!));});
        group.MapPost("/sync",async(JsonObject input,HttpRequest request)=>{
            if(input["baseline"] is not null and not JsonObject)return Results.BadRequest();
            if(!Guid.TryParse(input["operationId"]?.ToString(),out var operation)||operation==Guid.Empty||input["archive"] is not JsonObject local)return Results.BadRequest();
            var normalized=DiningSyncMerge.Normalize(local);var baseline=input["baseline"] is JsonObject old?DiningSyncMerge.Normalize(old):null;
            var payload=new JsonObject{["archive"]=normalized.DeepClone(),["baseline"]=baseline?.DeepClone()};
            // jsonb canonical text keeps retry hashes independent of field ordering.
            await using var c=new NpgsqlConnection(cs);await c.OpenAsync();await using var tx=await c.BeginTransactionAsync();
            var owner=ownerFor(request)!;
            await using(var gate=new NpgsqlCommand("SELECT pg_advisory_xact_lock(hashtextextended(@owner,704291))",c,tx)){gate.Parameters.AddWithValue("owner",owner);await gate.ExecuteNonQueryAsync();}
            string checksum;
            await using(var canonical=new NpgsqlCommand("SELECT @data::jsonb::text",c,tx)){canonical.Parameters.AddWithValue("data",payload.ToJsonString());checksum=Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes((string)(await canonical.ExecuteScalarAsync())!)));}
            await using(var seen=new NpgsqlCommand("SELECT payload_sha256 FROM account_dining_sync_operations WHERE owner_id=@owner AND operation_id=@operation",c,tx)){
                seen.Parameters.AddWithValue("owner",owner);seen.Parameters.AddWithValue("operation",operation);
                if(await seen.ExecuteScalarAsync() is string prior){if(prior!=checksum)return Results.Conflict(new{error="同步操作标识已用于不同内容。"});var repeated=await Read(c,owner,tx);await tx.CommitAsync();return Results.Json(repeated);}
            }
            JsonObject remote=DiningSyncMerge.Empty(),tombstones=new();
            await using(var current=new NpgsqlCommand("SELECT archive::text,tombstones::text FROM account_dining_archives WHERE owner_id=@owner FOR UPDATE",c,tx)){
                current.Parameters.AddWithValue("owner",owner);await using var r=await current.ExecuteReaderAsync();if(await r.ReadAsync()){remote=JsonNode.Parse(r.GetString(0))!.AsObject();tombstones=JsonNode.Parse(r.GetString(1))!.AsObject();}
            }
            var merged=DiningSyncMerge.Merge(remote,baseline,normalized,tombstones);
            await using(var save=new NpgsqlCommand("INSERT INTO account_dining_archives(owner_id,archive,tombstones) VALUES(@owner,@archive::jsonb,@tombstones::jsonb) ON CONFLICT(owner_id) DO UPDATE SET archive=EXCLUDED.archive,tombstones=EXCLUDED.tombstones,version=account_dining_archives.version+1,updated_at=now()",c,tx)){
                save.Parameters.AddWithValue("owner",owner);save.Parameters.AddWithValue("archive",merged.ToJsonString());save.Parameters.AddWithValue("tombstones",tombstones.ToJsonString());await save.ExecuteNonQueryAsync();
            }
            await using(var receipt=new NpgsqlCommand("INSERT INTO account_dining_sync_operations(owner_id,operation_id,payload_sha256) VALUES(@owner,@operation,@sha)",c,tx)){
                receipt.Parameters.AddWithValue("owner",owner);receipt.Parameters.AddWithValue("operation",operation);receipt.Parameters.AddWithValue("sha",checksum);await receipt.ExecuteNonQueryAsync();
            }
            var result=await Read(c,owner,tx);await tx.CommitAsync();return Results.Json(result);
        }).WithMetadata(new RequestSizeLimitAttribute(8*1024*1024));
    }
}
