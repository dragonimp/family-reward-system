using System.Globalization;
using System.Text.Json.Nodes;
using Npgsql;
using NpgsqlTypes;

internal static class FamilyConnectionEndpoints
{
    private static IResult Bad(string error) => Results.BadRequest(new { error });
    private static IResult Conflict(string error) => Results.Conflict(new { error });
    private static string Text(JsonObject body, string key) => body[key]?.ToString().Trim() ?? "";

    public static void MapFamilyConnectionEndpoints(
        this WebApplication app, string connectionString,
        Func<HttpRequest, Task<(string? Owner, IResult? Error)>> parentAccess,
        Func<HttpRequest, Task<(string? Key, string? Owner, IResult? Error)>> watchAccess)
    {
        app.MapGet("/api/family-connections", async (HttpRequest request) =>
        {
            var (owner, error) = await parentAccess(request);
            return error ?? Results.Json(await Read(connectionString, owner!, null));
        });
        app.MapPost("/api/family-connections", async (JsonObject body, HttpRequest request) =>
        {
            var (owner, error) = await parentAccess(request);
            if (error is not null) return error;
            if (!int.TryParse(Text(body, "childId"), out var childId)) return Bad("请选择孩子");
            var key = await CreditScoreStore.OwnedProfileKey(connectionString, childId, owner!);
            return key is null ? Results.StatusCode(403) : await Create(connectionString, key, owner!, "parent", body);
        });
        app.MapPost("/api/family-connections/{id:long}/entries", async (long id, JsonObject body, HttpRequest request) =>
        {
            var (owner, error) = await parentAccess(request);
            return error ?? await AddEntry(connectionString, id, owner!, null, "parent", body);
        });
        app.MapPost("/api/family-connections/{id:long}/transition", async (long id, JsonObject body, HttpRequest request) =>
        {
            var (owner, error) = await parentAccess(request);
            return error ?? await Transition(connectionString, id, owner!, null, "parent", body);
        });
        app.MapGet("/api/watch/family-connections", async (HttpRequest request) =>
        {
            var (key, owner, error) = await watchAccess(request);
            return error ?? Results.Json(await Read(connectionString, owner!, key));
        });
        app.MapPost("/api/watch/family-connections", async (JsonObject body, HttpRequest request) =>
        {
            var (key, owner, error) = await watchAccess(request);
            return error ?? await Create(connectionString, key!, owner!, "child", body);
        });
        app.MapPost("/api/watch/family-connections/{id:long}/entries", async (long id, JsonObject body, HttpRequest request) =>
        {
            var (key, owner, error) = await watchAccess(request);
            return error ?? await AddEntry(connectionString, id, owner!, key!, "child", body);
        });
        app.MapPost("/api/watch/family-connections/{id:long}/transition", async (long id, JsonObject body, HttpRequest request) =>
        {
            var (key, owner, error) = await watchAccess(request);
            return error ?? await Transition(connectionString, id, owner!, key!, "child", body);
        });
    }

    private static async Task<IResult> Create(string cs, string key, string owner, string role, JsonObject body)
    {
        var kind = Text(body, "kind"); var title = Text(body, "title"); var intent = Text(body, "intent");
        if (kind is not ("special_time" or "listen" or "reconnect" or "meeting")) return Bad("请选择亲子互动类型");
        if (title.Length is < 2 or > 160) return Bad("主题需为 2–160 字");
        if (kind == "listen" && intent is not ("share" or "comfort" or "ideas")) return Bad("请选择倾听方式");
        if (kind != "listen") intent = "";
        if (!Guid.TryParse(Text(body, "requestId"), out var requestId)) return Bad("请求编号无效");
        await using var conn = new NpgsqlConnection(cs); await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO family_connections(child_profile_key,parent_app_user_id,kind,title,intent,request_id,created_by)
            SELECT @key,@owner,@kind,@title,@intent,@request_id,@role
            WHERE EXISTS (SELECT 1 FROM child_user_bindings WHERE child_profile_key=@key AND parent_app_user_id=@owner)
            ON CONFLICT(child_profile_key,parent_app_user_id,request_id) DO NOTHING RETURNING id
            """, conn);
        cmd.Parameters.AddWithValue("key", key); cmd.Parameters.AddWithValue("owner", owner);
        cmd.Parameters.AddWithValue("kind", kind); cmd.Parameters.AddWithValue("title", title);
        cmd.Parameters.AddWithValue("intent", intent); cmd.Parameters.AddWithValue("request_id", requestId);
        cmd.Parameters.AddWithValue("role", role);
        var created = await cmd.ExecuteScalarAsync();
        if (created is null)
        {
            await using var check = new NpgsqlCommand("SELECT kind,title,intent FROM family_connections WHERE child_profile_key=@key AND parent_app_user_id=@owner AND request_id=@request_id", conn);
            check.Parameters.AddWithValue("key", key); check.Parameters.AddWithValue("owner", owner); check.Parameters.AddWithValue("request_id", requestId);
            await using var reader = await check.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return Results.StatusCode(403);
            if (reader.GetString(0) != kind || reader.GetString(1) != title || reader.GetString(2) != intent) return Conflict("请求编号已用于其他内容");
        }
        return Results.Json(await Read(cs, owner, role == "child" ? key : null));
    }

    private static async Task<IResult> AddEntry(string cs, long id, string owner, string? key, string role, JsonObject body)
    {
        var type = Text(body, "type"); var content = Text(body, "content");
        if (type is not ("message" or "feeling" or "hope" or "proposal" or "reflection")) return Bad("记录类型无效");
        if (content.Length is < 2 or > 500) return Bad("内容需为 2–500 字");
        if (!Guid.TryParse(Text(body, "requestId"), out var requestId)) return Bad("请求编号无效");
        await using var conn = new NpgsqlConnection(cs); await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        var thread = await LockThread(conn, tx, id, owner, key);
        if (thread is null) return Results.NotFound(new { error = "互动记录不存在" });
        if (thread.Value.Status is "completed" or "cancelled") return Conflict("这段互动已结束");
        if (type == "proposal" && thread.Value.Kind != "meeting") return Bad("只有家庭小会议可以提交提议");
        if (type is "feeling" or "hope" && thread.Value.Kind != "reconnect") return Bad("请在重连对话中记录感受和期待");
        if (type == "reflection" && thread.Value.Kind == "meeting" && thread.Value.Status != "trial") return Conflict("试行开始后才能写复盘");
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO family_connection_entries(connection_id,author_role,entry_type,content,request_id)
            VALUES(@id,@role,@type,@content,@request_id)
            ON CONFLICT(connection_id,request_id) DO NOTHING RETURNING id
            """, conn, tx);
        cmd.Parameters.AddWithValue("id", id); cmd.Parameters.AddWithValue("role", role);
        cmd.Parameters.AddWithValue("type", type); cmd.Parameters.AddWithValue("content", content);
        cmd.Parameters.AddWithValue("request_id", requestId);
        var inserted = await cmd.ExecuteScalarAsync();
        if (inserted is null)
        {
            await using var check = new NpgsqlCommand("SELECT author_role,entry_type,content FROM family_connection_entries WHERE connection_id=@id AND request_id=@request_id", conn, tx);
            check.Parameters.AddWithValue("id", id); check.Parameters.AddWithValue("request_id", requestId);
            await using var reader = await check.ExecuteReaderAsync();
            if (!await reader.ReadAsync() || reader.GetString(0) != role || reader.GetString(1) != type || reader.GetString(2) != content) return Conflict("请求编号已用于其他内容");
        }
        else
        {
            await using var touch = new NpgsqlCommand("UPDATE family_connections SET updated_at=CURRENT_TIMESTAMP WHERE id=@id", conn, tx);
            touch.Parameters.AddWithValue("id", id); await touch.ExecuteNonQueryAsync();
        }
        await tx.CommitAsync();
        return Results.Json(await Read(cs, owner, key));
    }

    private static async Task<IResult> Transition(string cs, long id, string owner, string? key, string role, JsonObject body)
    {
        var action = Text(body, "action");
        if (action is not ("schedule" or "complete" or "start_trial" or "review" or "cancel")) return Bad("操作无效");
        await using var conn = new NpgsqlConnection(cs); await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        var thread = await LockThread(conn, tx, id, owner, key);
        if (thread is null) return Results.NotFound(new { error = "互动记录不存在" });
        var (kind, status) = thread.Value;
        if (status is "completed" or "cancelled") return Conflict("这段互动已结束");
        string next; DateTimeOffset? at = null; string plan = "";
        switch (action)
        {
            case "schedule" when role == "parent" && kind == "special_time" && status == "open":
                if (!DateTimeOffset.TryParse(Text(body, "scheduledAt"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var scheduled)
                    || scheduled <= DateTimeOffset.UtcNow || scheduled > DateTimeOffset.UtcNow.AddMonths(3)) return Bad("请选择三个月内的未来时间");
                next = "scheduled"; at = scheduled; break;
            case "complete" when kind == "special_time" && status == "scheduled":
            case "complete" when kind == "listen" && status == "open":
                await using (var check = new NpgsqlCommand("SELECT COUNT(DISTINCT author_role) FROM family_connection_entries WHERE connection_id=@id", conn, tx))
                { check.Parameters.AddWithValue("id", id); if (Convert.ToInt32(await check.ExecuteScalarAsync()) < 2) return Conflict("双方交流后再结束倾听"); }
                next = "completed"; break;
            case "complete" when kind == "reconnect" && status == "open":
                await using (var check = new NpgsqlCommand("SELECT COUNT(DISTINCT author_role) FROM family_connection_entries WHERE connection_id=@id AND entry_type IN ('feeling','hope')", conn, tx))
                { check.Parameters.AddWithValue("id", id); if (Convert.ToInt32(await check.ExecuteScalarAsync()) < 2) return Conflict("双方都说出感受或期待后再结束重连"); }
                next = "completed"; break;
            case "start_trial" when role == "parent" && kind == "meeting" && status == "open":
                plan = Text(body, "plan");
                if (plan.Length is < 2 or > 500) return Bad("请写下本周试行的安排");
                await using (var check = new NpgsqlCommand("SELECT COUNT(DISTINCT author_role) FROM family_connection_entries WHERE connection_id=@id AND entry_type='proposal'", conn, tx))
                { check.Parameters.AddWithValue("id", id); if (Convert.ToInt32(await check.ExecuteScalarAsync()) < 2) return Conflict("请先听取家长和孩子各自的提议"); }
                next = "trial"; at = DateTimeOffset.UtcNow.AddDays(7); break;
            case "review" when role == "parent" && kind == "meeting" && status == "trial":
                await using (var check = new NpgsqlCommand("SELECT review_at FROM family_connections WHERE id=@id", conn, tx))
                { check.Parameters.AddWithValue("id", id); if ((DateTime) (await check.ExecuteScalarAsync())! > DateTime.UtcNow) return Conflict("七天试行结束后再复盘"); }
                await using (var check = new NpgsqlCommand("SELECT COUNT(DISTINCT author_role) FROM family_connection_entries WHERE connection_id=@id AND entry_type='reflection'", conn, tx))
                { check.Parameters.AddWithValue("id", id); if (Convert.ToInt32(await check.ExecuteScalarAsync()) < 2) return Conflict("双方都留下复盘后再结束会议"); }
                next = "completed"; break;
            case "cancel" when role == "parent": next = "cancelled"; break;
            default: return Conflict("当前阶段无法执行此操作");
        }
        await using var update = new NpgsqlCommand("""
            UPDATE family_connections SET status=@status,
              scheduled_at=CASE WHEN @action='schedule' THEN @at ELSE scheduled_at END,
              review_at=CASE WHEN @action='start_trial' THEN @at ELSE review_at END,
              trial_plan=CASE WHEN @action='start_trial' THEN @plan ELSE trial_plan END,
              updated_at=CURRENT_TIMESTAMP WHERE id=@id
            """, conn, tx);
        update.Parameters.AddWithValue("id", id); update.Parameters.AddWithValue("status", next);
        update.Parameters.AddWithValue("action", action); update.Parameters.AddWithValue("at", (object?)at?.UtcDateTime ?? DBNull.Value);
        update.Parameters.AddWithValue("plan", plan); await update.ExecuteNonQueryAsync();
        await tx.CommitAsync();
        return Results.Json(await Read(cs, owner, key));
    }

    private static async Task<(string Kind, string Status)?> LockThread(NpgsqlConnection conn, NpgsqlTransaction tx, long id, string owner, string? key)
    {
        await using var cmd = new NpgsqlCommand("SELECT kind,status FROM family_connections f WHERE id=@id AND parent_app_user_id=@owner AND (@key IS NULL OR child_profile_key=@key) AND EXISTS (SELECT 1 FROM child_user_bindings b WHERE b.parent_app_user_id=@owner AND b.child_profile_key=f.child_profile_key) FOR UPDATE", conn, tx);
        cmd.Parameters.AddWithValue("id", id); cmd.Parameters.AddWithValue("owner", owner);
        cmd.Parameters.Add("key", NpgsqlDbType.Varchar).Value = (object?)key ?? DBNull.Value;
        await using var reader = await cmd.ExecuteReaderAsync();
        return await reader.ReadAsync() ? (reader.GetString(0), reader.GetString(1)) : null;
    }

    private static async Task<object> Read(string cs, string owner, string? key)
    {
        await using var conn = new NpgsqlConnection(cs); await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("""
            SELECT f.id,f.child_profile_key,c.name,f.kind,f.title,f.intent,f.status,f.scheduled_at,f.review_at,f.trial_plan,f.created_by,f.created_at,f.updated_at
            FROM family_connections f JOIN child_profiles c ON c.profile_key=f.child_profile_key
            WHERE f.parent_app_user_id=@owner AND (@key IS NULL OR f.child_profile_key=@key)
              AND EXISTS (SELECT 1 FROM child_user_bindings b WHERE b.parent_app_user_id=@owner AND b.child_profile_key=f.child_profile_key)
            ORDER BY f.updated_at DESC,f.id DESC LIMIT 100
            """, conn);
        cmd.Parameters.AddWithValue("owner", owner); cmd.Parameters.Add("key", NpgsqlDbType.Varchar).Value = (object?)key ?? DBNull.Value;
        var rows = new List<object>(); var ids = new List<long>();
        await using (var reader = await cmd.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
            {
                var id = reader.GetInt64(0); ids.Add(id);
                rows.Add(new { id, childProfileKey=reader.GetString(1), childName=reader.GetString(2), kind=reader.GetString(3),
                    title=reader.GetString(4), intent=reader.GetString(5), status=reader.GetString(6),
                    scheduledAt=reader.IsDBNull(7) ? (DateTime?)null : reader.GetDateTime(7),
                    reviewAt=reader.IsDBNull(8) ? (DateTime?)null : reader.GetDateTime(8), trialPlan=reader.GetString(9),
                    createdBy=reader.GetString(10), createdAt=reader.GetDateTime(11), updatedAt=reader.GetDateTime(12) });
            }
        }
        var entries = new List<object>();
        if (ids.Count > 0)
        {
            await using var entryCmd = new NpgsqlCommand("SELECT id,connection_id,author_role,entry_type,content,created_at FROM family_connection_entries WHERE connection_id=ANY(@ids) ORDER BY created_at,id", conn);
            entryCmd.Parameters.AddWithValue("ids", ids.ToArray());
            await using var reader = await entryCmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) entries.Add(new { id=reader.GetInt64(0), connectionId=reader.GetInt64(1), authorRole=reader.GetString(2),
                type=reader.GetString(3), content=reader.GetString(4), createdAt=reader.GetDateTime(5) });
        }
        return new { threads=rows, entries };
    }
}
