using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Npgsql;

internal static class GenealogyEndpoints
{
    private static string Text(JsonObject body, string key) => body[key]?.ToString().Trim() ?? "";
    private static IResult Bad(string message) => Results.BadRequest(new { error = message });
    private static IResult Missing() => Results.NotFound(new { error = "族谱不存在或当前用户无权查看" });
    private static IResult Denied() => Results.Json(new { error = "只有族谱管理员可以修改" }, statusCode: 403);

    public static void MapGenealogyEndpoints(this WebApplication app, string cs,
        Func<HttpRequest, Task<(string? User, string? Name, IResult? Error)>> authorize)
    {
        app.MapGet("/api/genealogies", async (HttpRequest request) =>
        {
            var (user, _, error) = await authorize(request);
            if (error is not null) return error;
            await using var conn = await Open(cs);
            await using var cmd = new NpgsqlCommand("""
                SELECT t.id,t.name,t.surname,t.description,u.role,
                       (SELECT count(*) FROM genealogy_people p WHERE p.tree_id=t.id) AS people_count
                FROM genealogy_trees t JOIN genealogy_tree_users u ON u.tree_id=t.id
                WHERE u.app_user_id=@user ORDER BY t.updated_at DESC,t.id DESC
                """, conn);
            cmd.Parameters.AddWithValue("user", user!);
            var rows = new List<object>();
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) rows.Add(new { id=reader.GetInt64(0), name=reader.GetString(1), surname=reader.GetString(2), description=reader.GetString(3), role=reader.GetString(4), peopleCount=reader.GetInt64(5) });
            return Results.Json(rows);
        });

        app.MapGet("/api/genealogies/discover", async (HttpRequest request) =>
        {
            var (_, _, error) = await authorize(request);
            if (error is not null) return error;
            var q = request.Query["q"].ToString().Trim();
            if (q.Length is < 2 or > 50) return Bad("请输入 2–50 字的族谱名称或姓氏");
            await using var conn = await Open(cs);
            await using var cmd = new NpgsqlCommand("""
                SELECT id,name,surname FROM genealogy_trees
                WHERE strpos(lower(name),lower(@q))>0 OR strpos(lower(surname),lower(@q))>0
                ORDER BY CASE WHEN lower(name)=lower(@q) THEN 0 ELSE 1 END,updated_at DESC,id DESC LIMIT 20
                """, conn);
            cmd.Parameters.AddWithValue("q", q);
            var rows = new List<object>();
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) rows.Add(new { id=reader.GetInt64(0), name=reader.GetString(1), surname=reader.GetString(2) });
            return Results.Json(rows);
        });

        app.MapGet("/api/genealogies/my-join-requests", async (HttpRequest request) =>
        {
            var (user, _, error) = await authorize(request);
            if (error is not null) return error;
            await using var conn = await Open(cs);
            await using var cmd = new NpgsqlCommand("""
                SELECT r.id,r.tree_id,t.name,r.status,r.created_at
                FROM genealogy_join_requests r JOIN genealogy_trees t ON t.id=r.tree_id
                WHERE r.app_user_id=@user ORDER BY r.created_at DESC,r.id DESC LIMIT 100
                """, conn);
            cmd.Parameters.AddWithValue("user", user!);
            var rows = new List<object>();
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) rows.Add(new { id=reader.GetInt64(0),treeId=reader.GetInt64(1),treeName=reader.GetString(2),status=reader.GetString(3),createdAt=reader.GetDateTime(4) });
            return Results.Json(rows);
        });

        app.MapPost("/api/genealogies", async (JsonObject body, HttpRequest request) =>
        {
            var (user, username, error) = await authorize(request);
            if (error is not null) return error;
            var name=Text(body,"name"); var surname=Text(body,"surname"); var description=Text(body,"description");
            if (name.Length is < 2 or > 100 || surname.Length > 30 || description.Length > 500) return Bad("族谱名称需 2–100 字，姓氏不超过 30 字，简介不超过 500 字");
            await using var conn = await Open(cs);
            await using var tx = await conn.BeginTransactionAsync();
            await using var create = new NpgsqlCommand("INSERT INTO genealogy_trees(name,surname,description,created_by) VALUES(@name,@surname,@description,@user) RETURNING id",conn,tx);
            create.Parameters.AddWithValue("name",name); create.Parameters.AddWithValue("surname",surname); create.Parameters.AddWithValue("description",description); create.Parameters.AddWithValue("user",user!);
            var id=(long)(await create.ExecuteScalarAsync())!;
            await using var join = new NpgsqlCommand("INSERT INTO genealogy_tree_users(tree_id,app_user_id,role) VALUES(@id,@user,'owner')",conn,tx);
            join.Parameters.AddWithValue("id",id); join.Parameters.AddWithValue("user",user!); await join.ExecuteNonQueryAsync();
            await using var person = new NpgsqlCommand("INSERT INTO genealogy_people(tree_id,display_name,claimed_by) VALUES(@id,@name,@user)",conn,tx);
            person.Parameters.AddWithValue("id",id); person.Parameters.AddWithValue("name",SafeName(username)); person.Parameters.AddWithValue("user",user!); await person.ExecuteNonQueryAsync();
            await tx.CommitAsync();
            return Results.Created($"/api/genealogies/{id}",new { id,name,surname,description,role="owner",peopleCount=1 });
        });

        app.MapGet("/api/genealogies/{id:long}", async (long id, HttpRequest request) =>
        {
            var (user, _, error) = await authorize(request);
            if (error is not null) return error;
            await using var conn = await Open(cs);
            await using var cmd = new NpgsqlCommand("""
                SELECT t.name,t.surname,t.description,u.role,
                       (SELECT count(*) FROM genealogy_tree_users x WHERE x.tree_id=t.id) AS user_count,
                       (SELECT count(*) FROM genealogy_people p WHERE p.tree_id=t.id) AS people_count
                FROM genealogy_trees t JOIN genealogy_tree_users u ON u.tree_id=t.id
                WHERE t.id=@id AND u.app_user_id=@user
                """,conn);
            cmd.Parameters.AddWithValue("id",id); cmd.Parameters.AddWithValue("user",user!);
            await using var reader=await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? Results.Json(new { id,name=reader.GetString(0),surname=reader.GetString(1),description=reader.GetString(2),role=reader.GetString(3),memberCount=reader.GetInt64(4),peopleCount=reader.GetInt64(5) }) : Missing();
        });

        app.MapPost("/api/genealogies/{id:long}/join-requests", async (long id, JsonObject body, HttpRequest request) =>
        {
            var (user, username, error) = await authorize(request);
            if (error is not null) return error;
            var displayName=Text(body,"displayName"); var message=Text(body,"message");
            if (displayName.Length is < 2 or > 80 || message.Length>300) return Bad("姓名需 2–80 字，申请说明不超过 300 字");
            await using var conn=await Open(cs);
            await using var cmd=new NpgsqlCommand("""
                INSERT INTO genealogy_join_requests(tree_id,app_user_id,account_name,display_name,message)
                SELECT t.id,@user,@account,@name,@message FROM genealogy_trees t WHERE t.id=@id
                  AND NOT EXISTS(SELECT 1 FROM genealogy_tree_users u WHERE u.tree_id=t.id AND u.app_user_id=@user)
                ON CONFLICT DO NOTHING RETURNING id
                """,conn);
            cmd.Parameters.AddWithValue("id",id); cmd.Parameters.AddWithValue("user",user!); cmd.Parameters.AddWithValue("account",SafeAccountName(username)); cmd.Parameters.AddWithValue("name",displayName); cmd.Parameters.AddWithValue("message",message);
            var requestId=await cmd.ExecuteScalarAsync();
            if (requestId is null) return Results.Conflict(new { error="族谱不存在、已加入或申请正在等待审核" });
            return Results.Created($"/api/genealogies/{id}/join-requests/{requestId}",new { id=requestId,treeId=id,displayName,status="pending" });
        });

        app.MapGet("/api/genealogies/{id:long}/join-requests", async (long id, HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if (error is not null) return error;
            await using var conn=await Open(cs);
            if (await Role(conn,id,user!)!="owner") return Denied();
            await using var cmd=new NpgsqlCommand("SELECT id,display_name,account_name,message,created_at FROM genealogy_join_requests WHERE tree_id=@id AND status='pending' ORDER BY created_at,id LIMIT 100",conn);
            cmd.Parameters.AddWithValue("id",id);
            var rows=new List<object>();
            await using var reader=await cmd.ExecuteReaderAsync();
            while(await reader.ReadAsync()) rows.Add(new { id=reader.GetInt64(0),displayName=reader.GetString(1),accountName=reader.GetString(2),message=reader.GetString(3),createdAt=reader.GetDateTime(4) });
            return Results.Json(rows);
        });

        app.MapPost("/api/genealogies/{id:long}/join-requests/{requestId:long}/decision", async (long id,long requestId,JsonObject body,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if (error is not null) return error;
            var decision=Text(body,"decision");
            if (decision is not ("approve" or "reject")) return Bad("请选择通过或拒绝");
            var personIdText=Text(body,"personId");
            if (personIdText.Length>0 && (!long.TryParse(personIdText,out var parsedPersonId) || parsedPersonId<=0)) return Bad("关联人物无效");
            var personId=personIdText.Length>0 ? long.Parse(personIdText) : 0;
            await using var conn=await Open(cs);
            await using var tx=await conn.BeginTransactionAsync();
            if (await Role(conn,id,user!,tx)!="owner") return Denied();
            string applicant,displayName;
            await using(var get=new NpgsqlCommand("SELECT app_user_id,display_name FROM genealogy_join_requests WHERE tree_id=@id AND id=@request AND status='pending' FOR UPDATE",conn,tx))
            {
                get.Parameters.AddWithValue("id",id); get.Parameters.AddWithValue("request",requestId);
                await using var reader=await get.ExecuteReaderAsync();
                if(!await reader.ReadAsync()) return Results.Conflict(new { error="申请不存在或已处理" });
                applicant=reader.GetString(0); displayName=reader.GetString(1);
            }
            var status=decision=="approve"?"approved":"rejected";
            await using(var update=new NpgsqlCommand("UPDATE genealogy_join_requests SET status=@status,decided_by=@user,decided_at=CURRENT_TIMESTAMP WHERE tree_id=@id AND id=@request",conn,tx))
            {
                update.Parameters.AddWithValue("status",status); update.Parameters.AddWithValue("user",user!); update.Parameters.AddWithValue("id",id); update.Parameters.AddWithValue("request",requestId); await update.ExecuteNonQueryAsync();
            }
            if(status=="approved")
            {
                await using var join=new NpgsqlCommand("INSERT INTO genealogy_tree_users(tree_id,app_user_id,role) VALUES(@id,@user,'member') ON CONFLICT DO NOTHING",conn,tx);
                join.Parameters.AddWithValue("id",id); join.Parameters.AddWithValue("user",applicant); await join.ExecuteNonQueryAsync();
                if(personId>0)
                {
                    await using var claim=new NpgsqlCommand("UPDATE genealogy_people SET claimed_by=@user,updated_at=CURRENT_TIMESTAMP WHERE tree_id=@id AND id=@person AND claimed_by IS NULL RETURNING id",conn,tx);
                    claim.Parameters.AddWithValue("id",id); claim.Parameters.AddWithValue("person",personId); claim.Parameters.AddWithValue("user",applicant);
                    if(await claim.ExecuteScalarAsync() is null) return Results.Conflict(new { error="选定的人物不存在或已关联其他账号" });
                }
                else
                {
                    await using var person=new NpgsqlCommand("INSERT INTO genealogy_people(tree_id,display_name,claimed_by) VALUES(@id,@name,@user) ON CONFLICT DO NOTHING",conn,tx);
                    person.Parameters.AddWithValue("id",id); person.Parameters.AddWithValue("name",displayName); person.Parameters.AddWithValue("user",applicant); await person.ExecuteNonQueryAsync();
                }
            }
            await tx.CommitAsync();
            return Results.Json(new { id=requestId,status });
        });

        app.MapGet("/api/genealogies/{id:long}/people", async (long id,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            var q=request.Query["q"].ToString().Trim();
            if(q.Length>80) return Bad("搜索内容不能超过 80 字");
            await using var conn=await Open(cs);
            if(await Role(conn,id,user!) is null) return Missing();
            await using var cmd=new NpgsqlCommand("""
                SELECT id,display_name,generation_label,branch_name,note,claimed_by IS NOT NULL,claimed_by=@user,gender,birth_year,birth_month,birth_day
                FROM genealogy_people WHERE tree_id=@id AND (@q='' OR strpos(lower(display_name),lower(@q))>0 OR strpos(lower(branch_name),lower(@q))>0)
                ORDER BY generation_label,display_name,id LIMIT 101
                """,conn);
            cmd.Parameters.AddWithValue("id",id); cmd.Parameters.AddWithValue("q",q); cmd.Parameters.AddWithValue("user",user!);
            var rows=new List<object>();
            await using var reader=await cmd.ExecuteReaderAsync();
            while(await reader.ReadAsync()) rows.Add(Person(reader));
            return Results.Json(new { people=rows.Take(100),hasMore=rows.Count>100 });
        });

        app.MapPost("/api/genealogies/{id:long}/people", async (long id,JsonObject body,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            var name=Text(body,"displayName");var generation=Text(body,"generationLabel");var branch=Text(body,"branchName");var note=Text(body,"note");
            if(!ValidPerson(name,generation,branch,note)) return Bad("姓名需 2–80 字，辈分不超过 40 字，支系不超过 80 字，备注不超过 500 字");
            if(!GenealogyPersonDetailsParser.TryRead(body,out var details,out var detailsError)) return Bad(detailsError);
            await using var conn=await Open(cs);
            if(await Role(conn,id,user!)!="owner") return Denied();
            await using var cmd=new NpgsqlCommand("INSERT INTO genealogy_people(tree_id,display_name,generation_label,branch_name,note,gender,birth_year,birth_month,birth_day) VALUES(@id,@name,@generation,@branch,@note,@gender,@birthYear,@birthMonth,@birthDay) RETURNING id",conn);
            AddPersonParameters(cmd,id,name,generation,branch,note);
            AddPersonDetailsParameters(cmd,details);
            var personId=(long)(await cmd.ExecuteScalarAsync())!;
            return Results.Created($"/api/genealogies/{id}/people/{personId}",new { id=personId,displayName=name,generationLabel=generation,branchName=branch,note,gender=details.Gender,birthYear=details.BirthYear,birthMonth=details.BirthMonth,birthDay=details.BirthDay,isLinked=false,isSelf=false });
        });

        app.MapGet("/api/genealogies/{id:long}/people/{personId:long}", async (long id,long personId,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            await using var conn=await Open(cs);
            if(await Role(conn,id,user!) is null) return Missing();
            await using var cmd=new NpgsqlCommand("""
                SELECT id,display_name,generation_label,branch_name,note,claimed_by IS NOT NULL,claimed_by=@user,gender,birth_year,birth_month,birth_day
                FROM genealogy_people WHERE tree_id=@id AND id=@person
                """,conn);
            cmd.Parameters.AddWithValue("id",id);cmd.Parameters.AddWithValue("person",personId);cmd.Parameters.AddWithValue("user",user!);
            await using var reader=await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? Results.Json(Person(reader)) : Results.NotFound(new { error="成员不存在" });
        });

        app.MapPut("/api/genealogies/{id:long}/people/{personId:long}", async (long id,long personId,JsonObject body,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            var name=Text(body,"displayName");var generation=Text(body,"generationLabel");var branch=Text(body,"branchName");var note=Text(body,"note");
            if(!ValidPerson(name,generation,branch,note)) return Bad("姓名需 2–80 字，辈分不超过 40 字，支系不超过 80 字，备注不超过 500 字");
            if(!GenealogyPersonDetailsParser.TryRead(body,out var details,out var detailsError)) return Bad(detailsError);
            await using var conn=await Open(cs);
            if(await Role(conn,id,user!)!="owner") return Denied();
            await using var cmd=new NpgsqlCommand("UPDATE genealogy_people SET display_name=@name,generation_label=@generation,branch_name=@branch,note=@note,gender=CASE WHEN @genderProvided THEN @gender ELSE gender END,birth_year=CASE WHEN @birthProvided THEN @birthYear ELSE birth_year END,birth_month=CASE WHEN @birthProvided THEN @birthMonth ELSE birth_month END,birth_day=CASE WHEN @birthProvided THEN @birthDay ELSE birth_day END,updated_at=CURRENT_TIMESTAMP WHERE tree_id=@id AND id=@person RETURNING gender,birth_year,birth_month,birth_day",conn);
            AddPersonParameters(cmd,id,name,generation,branch,note);cmd.Parameters.AddWithValue("person",personId);
            AddPersonDetailsParameters(cmd,details);
            await using var reader=await cmd.ExecuteReaderAsync();
            return !await reader.ReadAsync() ? Results.NotFound(new { error="成员不存在" }) : Results.Json(new { id=personId,displayName=name,generationLabel=generation,branchName=branch,note,gender=reader.GetString(0),birthYear=reader.IsDBNull(1)?(short?)null:reader.GetInt16(1),birthMonth=reader.IsDBNull(2)?(short?)null:reader.GetInt16(2),birthDay=reader.IsDBNull(3)?(short?)null:reader.GetInt16(3) });
        });

        app.MapPost("/api/genealogies/{id:long}/people/{personId:long}/invitations", async (long id,long personId,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            await using var conn=await Open(cs);
            await using var tx=await conn.BeginTransactionAsync();
            if(await Role(conn,id,user!,tx)!="owner") return Denied();
            await using(var guard=new NpgsqlCommand("SELECT pg_advisory_xact_lock(@id)",conn,tx))
            {guard.Parameters.AddWithValue("id",id);await guard.ExecuteNonQueryAsync();}
            await using(var person=new NpgsqlCommand("SELECT claimed_by FROM genealogy_people WHERE tree_id=@id AND id=@person FOR UPDATE",conn,tx))
            {
                person.Parameters.AddWithValue("id",id);person.Parameters.AddWithValue("person",personId);
                await using var reader=await person.ExecuteReaderAsync();
                if(!await reader.ReadAsync()) return Results.NotFound(new { error="成员不存在" });
                if(!reader.IsDBNull(0)) return Results.Conflict(new { error="该成员已关联用户，无需邀请" });
            }
            await using(var revoke=new NpgsqlCommand("UPDATE genealogy_person_invitations SET revoked_at=CURRENT_TIMESTAMP WHERE tree_id=@id AND person_id=@person AND revoked_at IS NULL AND accepted_at IS NULL",conn,tx))
            {revoke.Parameters.AddWithValue("id",id);revoke.Parameters.AddWithValue("person",personId);await revoke.ExecuteNonQueryAsync();}
            var token=Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
            await using(var insert=new NpgsqlCommand("INSERT INTO genealogy_person_invitations(tree_id,person_id,token_hash,created_by,expires_at) VALUES(@id,@person,@hash,@user,CURRENT_TIMESTAMP+INTERVAL '7 days') RETURNING expires_at",conn,tx))
            {
                insert.Parameters.AddWithValue("id",id);insert.Parameters.AddWithValue("person",personId);insert.Parameters.AddWithValue("hash",TokenHash(token));insert.Parameters.AddWithValue("user",user!);
                var expiresAt=(DateTime)(await insert.ExecuteScalarAsync())!;
                await tx.CommitAsync();
                return Results.Json(new { path=$"/genealogy/invite/{token}",expiresAt });
            }
        });

        app.MapGet("/api/genealogies/invitations/{token}", async (string token,HttpRequest request) =>
        {
            var (_, _, error)=await authorize(request);
            if(error is not null) return error;
            if(!ValidToken(token)) return Results.NotFound(new { error="邀请链接无效" });
            await using var conn=await Open(cs);
            await using var cmd=new NpgsqlCommand("""
                SELECT i.tree_id,i.person_id,t.name,p.display_name,i.expires_at,
                  i.revoked_at IS NULL AND i.accepted_at IS NULL AND i.expires_at>CURRENT_TIMESTAMP AND p.claimed_by IS NULL
                FROM genealogy_person_invitations i
                JOIN genealogy_trees t ON t.id=i.tree_id
                JOIN genealogy_people p ON p.tree_id=i.tree_id AND p.id=i.person_id
                WHERE i.token_hash=@hash
                """,conn);
            cmd.Parameters.AddWithValue("hash",TokenHash(token));
            await using var reader=await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync()
                ? Results.Json(new { treeId=reader.GetInt64(0),personId=reader.GetInt64(1),treeName=reader.GetString(2),personName=reader.GetString(3),expiresAt=reader.GetDateTime(4),available=reader.GetBoolean(5) })
                : Results.NotFound(new { error="邀请链接无效" });
        });

        app.MapPost("/api/genealogies/invitations/{token}/accept", async (string token,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            if(!ValidToken(token)) return Results.NotFound(new { error="邀请链接无效" });
            await using var conn=await Open(cs);
            await using var tx=await conn.BeginTransactionAsync();
            await using(var lookup=new NpgsqlCommand("SELECT tree_id FROM genealogy_person_invitations WHERE token_hash=@hash",conn,tx))
            {
                lookup.Parameters.AddWithValue("hash",TokenHash(token));
                if(await lookup.ExecuteScalarAsync() is not long foundTree) return Results.Conflict(new { error="邀请已过期、已使用或已撤销" });
                await using var guard=new NpgsqlCommand("SELECT pg_advisory_xact_lock(@id)",conn,tx);
                guard.Parameters.AddWithValue("id",foundTree);await guard.ExecuteNonQueryAsync();
            }
            long invitationId,treeId,personId;
            string inviter;
            await using(var invite=new NpgsqlCommand("SELECT id,tree_id,person_id,created_by FROM genealogy_person_invitations WHERE token_hash=@hash AND revoked_at IS NULL AND accepted_at IS NULL AND expires_at>CURRENT_TIMESTAMP FOR UPDATE",conn,tx))
            {
                invite.Parameters.AddWithValue("hash",TokenHash(token));
                await using var reader=await invite.ExecuteReaderAsync();
                if(!await reader.ReadAsync()) return Results.Conflict(new { error="邀请已过期、已使用或已撤销" });
                invitationId=reader.GetInt64(0);treeId=reader.GetInt64(1);personId=reader.GetInt64(2);inviter=reader.GetString(3);
            }
            await using(var person=new NpgsqlCommand("SELECT claimed_by FROM genealogy_people WHERE tree_id=@id AND id=@person FOR UPDATE",conn,tx))
            {
                person.Parameters.AddWithValue("id",treeId);person.Parameters.AddWithValue("person",personId);
                await using var reader=await person.ExecuteReaderAsync();
                if(!await reader.ReadAsync() || !reader.IsDBNull(0)) return Results.Conflict(new { error="该成员已经关联其他用户" });
            }
            await using(var existing=new NpgsqlCommand("SELECT id FROM genealogy_people WHERE tree_id=@id AND claimed_by=@user",conn,tx))
            {
                existing.Parameters.AddWithValue("id",treeId);existing.Parameters.AddWithValue("user",user!);
                if(await existing.ExecuteScalarAsync() is not null) return Results.Conflict(new { error="你在该族谱已关联其他人物" });
            }
            await using(var join=new NpgsqlCommand("INSERT INTO genealogy_tree_users(tree_id,app_user_id,role) VALUES(@id,@user,'member') ON CONFLICT DO NOTHING",conn,tx))
            {join.Parameters.AddWithValue("id",treeId);join.Parameters.AddWithValue("user",user!);await join.ExecuteNonQueryAsync();}
            await using(var claim=new NpgsqlCommand("UPDATE genealogy_people SET claimed_by=@user,updated_at=CURRENT_TIMESTAMP WHERE tree_id=@id AND id=@person",conn,tx))
            {claim.Parameters.AddWithValue("id",treeId);claim.Parameters.AddWithValue("person",personId);await claim.ExecuteNonQueryAsync();}
            await using(var consume=new NpgsqlCommand("UPDATE genealogy_person_invitations SET accepted_by=@user,accepted_at=CURRENT_TIMESTAMP WHERE id=@invite",conn,tx))
            {consume.Parameters.AddWithValue("user",user!);consume.Parameters.AddWithValue("invite",invitationId);await consume.ExecuteNonQueryAsync();}
            await using(var requestUpdate=new NpgsqlCommand("UPDATE genealogy_join_requests SET status='approved',decided_by=@inviter,decided_at=CURRENT_TIMESTAMP WHERE tree_id=@id AND app_user_id=@user AND status='pending'",conn,tx))
            {requestUpdate.Parameters.AddWithValue("id",treeId);requestUpdate.Parameters.AddWithValue("user",user!);requestUpdate.Parameters.AddWithValue("inviter",inviter);await requestUpdate.ExecuteNonQueryAsync();}
            await tx.CommitAsync();
            return Results.Json(new { treeId,personId });
        });

        app.MapGet("/api/genealogies/{id:long}/relationships", async (long id,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            await using var conn=await Open(cs);
            if(await Role(conn,id,user!) is null) return Missing();
            await using var cmd=new NpgsqlCommand("""
                SELECT r.id,r.from_person_id,r.to_person_id,r.kind,p1.display_name,p2.display_name
                FROM genealogy_relationships r
                JOIN genealogy_people p1 ON p1.tree_id=r.tree_id AND p1.id=r.from_person_id
                JOIN genealogy_people p2 ON p2.tree_id=r.tree_id AND p2.id=r.to_person_id
                WHERE r.tree_id=@id ORDER BY r.id LIMIT 2000
                """,conn);
            cmd.Parameters.AddWithValue("id",id);
            var rows=new List<object>();
            await using var reader=await cmd.ExecuteReaderAsync();
            while(await reader.ReadAsync()) rows.Add(new { id=reader.GetInt64(0),fromPersonId=reader.GetInt64(1),toPersonId=reader.GetInt64(2),kind=reader.GetString(3),fromName=reader.GetString(4),toName=reader.GetString(5) });
            return Results.Json(rows);
        });

        app.MapGet("/api/genealogies/{id:long}/people/{personId:long}/inferred-relationships", async (long id,long personId,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            await using var conn=await Open(cs);
            await using var tx=await conn.BeginTransactionAsync(System.Data.IsolationLevel.RepeatableRead);
            if(await Role(conn,id,user!,tx) is null) return Missing();
            var names=new Dictionary<long,string>();
            await using(var people=new NpgsqlCommand("SELECT id,display_name FROM genealogy_people WHERE tree_id=@id",conn,tx))
            {
                people.Parameters.AddWithValue("id",id);
                await using var reader=await people.ExecuteReaderAsync();
                while(await reader.ReadAsync()) names.Add(reader.GetInt64(0),reader.GetString(1));
            }
            if(!names.ContainsKey(personId)) return Results.NotFound(new { error="成员不存在" });
            var edges=new List<GenealogyBaseRelationship>();
            await using(var relations=new NpgsqlCommand("SELECT from_person_id,to_person_id,kind FROM genealogy_relationships WHERE tree_id=@id",conn,tx))
            {
                relations.Parameters.AddWithValue("id",id);
                await using var reader=await relations.ExecuteReaderAsync();
                while(await reader.ReadAsync()) edges.Add(new(reader.GetInt64(0),reader.GetInt64(1),reader.GetString(2)));
            }
            await tx.CommitAsync();
            return Results.Json(GenealogyInference.Infer(personId,names,edges));
        });

        app.MapPost("/api/genealogies/{id:long}/relationships", async (long id,JsonObject body,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            var kind=Text(body,"kind");
            if(kind is not ("parent" or "spouse") || !long.TryParse(Text(body,"fromPersonId"),out var from) || !long.TryParse(Text(body,"toPersonId"),out var to) || from<=0 || to<=0 || from==to) return Bad("请选择两个不同的成员及关系");
            if(kind=="spouse" && from>to) (from,to)=(to,from);
            await using var conn=await Open(cs);
            await using var tx=await conn.BeginTransactionAsync();
            if(await Role(conn,id,user!,tx)!="owner") return Denied();
            await using(var guard=new NpgsqlCommand("SELECT pg_advisory_xact_lock(@id)",conn,tx)) {guard.Parameters.AddWithValue("id",id);await guard.ExecuteNonQueryAsync();}
            await using(var count=new NpgsqlCommand("SELECT count(*) FROM genealogy_people WHERE tree_id=@id AND id IN (@from,@to)",conn,tx))
            {count.Parameters.AddWithValue("id",id);count.Parameters.AddWithValue("from",from);count.Parameters.AddWithValue("to",to);if((long)(await count.ExecuteScalarAsync())! != 2) return Bad("成员不属于当前族谱");}
            if(kind=="parent")
            {
                await using var cycle=new NpgsqlCommand("""
                    WITH RECURSIVE descendants(id) AS (
                      SELECT to_person_id FROM genealogy_relationships WHERE tree_id=@id AND kind='parent' AND from_person_id=@child
                      UNION
                      SELECT r.to_person_id FROM genealogy_relationships r JOIN descendants d ON r.from_person_id=d.id WHERE r.tree_id=@id AND r.kind='parent'
                    ) SELECT EXISTS(SELECT 1 FROM descendants WHERE id=@parent)
                    """,conn,tx);
                cycle.Parameters.AddWithValue("id",id);cycle.Parameters.AddWithValue("child",to);cycle.Parameters.AddWithValue("parent",from);
                if(await cycle.ExecuteScalarAsync() is true) return Results.Conflict(new { error="不能形成祖先循环" });
            }
            await using var cmd=new NpgsqlCommand("INSERT INTO genealogy_relationships(tree_id,from_person_id,to_person_id,kind) VALUES(@id,@from,@to,@kind) ON CONFLICT DO NOTHING RETURNING id",conn,tx);
            cmd.Parameters.AddWithValue("id",id);cmd.Parameters.AddWithValue("from",from);cmd.Parameters.AddWithValue("to",to);cmd.Parameters.AddWithValue("kind",kind);
            var relationId=await cmd.ExecuteScalarAsync();
            if(relationId is null) return Results.Conflict(new { error="关系已存在" });
            await tx.CommitAsync();
            return Results.Created($"/api/genealogies/{id}/relationships/{relationId}",new { id=relationId,fromPersonId=from,toPersonId=to,kind });
        });

        app.MapDelete("/api/genealogies/{id:long}/relationships/{relationId:long}", async (long id,long relationId,HttpRequest request) =>
        {
            var (user, _, error)=await authorize(request);
            if(error is not null) return error;
            await using var conn=await Open(cs);
            if(await Role(conn,id,user!)!="owner") return Denied();
            await using var cmd=new NpgsqlCommand("DELETE FROM genealogy_relationships WHERE tree_id=@id AND id=@relation",conn);
            cmd.Parameters.AddWithValue("id",id);cmd.Parameters.AddWithValue("relation",relationId);
            return await cmd.ExecuteNonQueryAsync()>0 ? Results.NoContent() : Results.NotFound(new { error="关系不存在" });
        });
    }

    private static async Task<NpgsqlConnection> Open(string cs) {var conn=new NpgsqlConnection(cs);await conn.OpenAsync();return conn;}
    private static async Task<string?> Role(NpgsqlConnection conn,long id,string user,NpgsqlTransaction? tx=null)
    {
        await using var cmd=new NpgsqlCommand("SELECT role FROM genealogy_tree_users WHERE tree_id=@id AND app_user_id=@user",conn,tx);
        cmd.Parameters.AddWithValue("id",id);cmd.Parameters.AddWithValue("user",user);
        return await cmd.ExecuteScalarAsync() as string;
    }
    private static string SafeName(string? name) => string.IsNullOrWhiteSpace(name) ? "新成员" : name.Trim()[..Math.Min(name.Trim().Length,80)];
    private static string SafeAccountName(string? name) => string.IsNullOrWhiteSpace(name) ? "未知账号" : name.Trim()[..Math.Min(name.Trim().Length,160)];
    private static bool ValidToken(string token) => token.Length==64 && token.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static string TokenHash(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();
    private static bool ValidPerson(string name,string generation,string branch,string note) => name.Length is >=2 and <=80 && generation.Length<=40 && branch.Length<=80 && note.Length<=500;
    private static void AddPersonParameters(NpgsqlCommand cmd,long id,string name,string generation,string branch,string note)
    {cmd.Parameters.AddWithValue("id",id);cmd.Parameters.AddWithValue("name",name);cmd.Parameters.AddWithValue("generation",generation);cmd.Parameters.AddWithValue("branch",branch);cmd.Parameters.AddWithValue("note",note);}
    private static void AddPersonDetailsParameters(NpgsqlCommand cmd,GenealogyPersonDetails details)
    {
        cmd.Parameters.AddWithValue("gender",details.Gender);
        cmd.Parameters.AddWithValue("birthYear",NpgsqlTypes.NpgsqlDbType.Smallint,(object?)details.BirthYear ?? DBNull.Value);
        cmd.Parameters.AddWithValue("birthMonth",NpgsqlTypes.NpgsqlDbType.Smallint,(object?)details.BirthMonth ?? DBNull.Value);
        cmd.Parameters.AddWithValue("birthDay",NpgsqlTypes.NpgsqlDbType.Smallint,(object?)details.BirthDay ?? DBNull.Value);
        cmd.Parameters.AddWithValue("genderProvided",details.GenderProvided);
        cmd.Parameters.AddWithValue("birthProvided",details.BirthProvided);
    }
    private static object Person(NpgsqlDataReader reader) => new { id=reader.GetInt64(0),displayName=reader.GetString(1),generationLabel=reader.GetString(2),branchName=reader.GetString(3),note=reader.GetString(4),isLinked=reader.GetBoolean(5),isSelf=!reader.IsDBNull(6) && reader.GetBoolean(6),gender=reader.GetString(7),birthYear=reader.IsDBNull(8)?(short?)null:reader.GetInt16(8),birthMonth=reader.IsDBNull(9)?(short?)null:reader.GetInt16(9),birthDay=reader.IsDBNull(10)?(short?)null:reader.GetInt16(10) };
}
