using System.Globalization;
using System.Text.Json.Nodes;
using Npgsql;
using NpgsqlTypes;

internal static class CreditScoreEndpoints
{
    public static void MapCreditScoreEndpoints(
        this WebApplication app,
        string connectionString,
        Func<HttpRequest, Task<(string? Owner, IResult? Error)>> parentAccess,
        Func<HttpRequest, Task<(string? ProfileKey, IResult? Error)>> watchAccess)
    {
        async Task<(string? Key, string? Owner, IResult? Error)> ParentChild(int childId, HttpRequest request)
        {
            var (owner, error) = await parentAccess(request);
            if (error is not null) return (null, null, error);
            var key = await CreditScoreStore.OwnedProfileKey(connectionString, childId, owner!);
            return key is null
                ? (null, null, Results.Json(new { error = "孩子不存在，或不属于当前家长" }, statusCode: 403))
                : (key, owner, null);
        }

        app.MapGet("/api/credit/overview", async (HttpRequest request) =>
        {
            var (owner, error) = await parentAccess(request);
            return error ?? Results.Json(await CreditScoreStore.Overview(connectionString, owner!));
        });
        app.MapGet("/api/children/{childId:int}/credit", async (int childId, HttpRequest request) =>
        {
            var access = await ParentChild(childId, request);
            return access.Error ?? Results.Json(await CreditScoreStore.Read(connectionString, access.Key!));
        });
        app.MapPost("/api/children/{childId:int}/credit/enable", async (int childId, HttpRequest request) =>
        {
            var access = await ParentChild(childId, request);
            return access.Error ?? await CreditScoreStore.Enable(connectionString, access.Key!, access.Owner!);
        });
        app.MapPost("/api/children/{childId:int}/credit/commitments", async (int childId, JsonObject body, HttpRequest request) =>
        {
            var access = await ParentChild(childId, request);
            return access.Error ?? await CreditScoreStore.CreateCommitment(connectionString, access.Key!, access.Owner!, body);
        });
        app.MapPost("/api/children/{childId:int}/credit/commitments/{commitmentId:long}/resolve", async (int childId, long commitmentId, JsonObject body, HttpRequest request) =>
        {
            var access = await ParentChild(childId, request);
            return access.Error ?? await CreditScoreStore.ResolveCommitment(connectionString, access.Key!, access.Owner!, commitmentId, body);
        });
        app.MapPost("/api/children/{childId:int}/credit/adjustments", async (int childId, JsonObject body, HttpRequest request) =>
        {
            var access = await ParentChild(childId, request);
            return access.Error ?? await CreditScoreStore.Adjust(connectionString, access.Key!, access.Owner!, body);
        });
        app.MapPost("/api/children/{childId:int}/credit/events/{eventId:long}/reverse", async (int childId, long eventId, JsonObject body, HttpRequest request) =>
        {
            var access = await ParentChild(childId, request);
            return access.Error ?? await CreditScoreStore.Reverse(connectionString, access.Key!, access.Owner!, eventId, body);
        });
        app.MapPost("/api/children/{childId:int}/credit/disputes/{disputeId:long}/resolve", async (int childId, long disputeId, JsonObject body, HttpRequest request) =>
        {
            var access = await ParentChild(childId, request);
            return access.Error ?? await CreditScoreStore.ResolveDispute(connectionString, access.Key!, access.Owner!, disputeId, body);
        });
        app.MapGet("/api/watch/credit", async (HttpRequest request) =>
        {
            var (key, error) = await watchAccess(request);
            return error ?? Results.Json(await CreditScoreStore.Read(connectionString, key!));
        });
        app.MapPost("/api/watch/credit/commitments/{commitmentId:long}/complete", async (long commitmentId, HttpRequest request) =>
        {
            var (key, error) = await watchAccess(request);
            return error ?? await CreditScoreStore.RequestCompletion(connectionString, key!, commitmentId);
        });
        app.MapPost("/api/watch/credit/events/{eventId:long}/dispute", async (long eventId, JsonObject body, HttpRequest request) =>
        {
            var (key, error) = await watchAccess(request);
            return error ?? await CreditScoreStore.Dispute(connectionString, key!, eventId, body);
        });
    }
}

internal static class CreditScoreStore
{
    private static IResult Bad(string message) => Results.BadRequest(new { error = message });
    private static IResult Conflict(string message) => Results.Conflict(new { error = message });
    private static string Text(JsonObject body, string key) => body[key]?.ToString().Trim() ?? "";
    private static Guid? RequestId(JsonObject body) => Guid.TryParse(Text(body, "requestId"), out var id) ? id : null;

    public static async Task<string?> OwnedProfileKey(string connectionString, int childId, string owner)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("""
            SELECT c.profile_key FROM children c
            JOIN child_user_bindings b ON b.child_profile_key = c.profile_key
            JOIN child_profiles p ON p.profile_key = c.profile_key
            WHERE c.id = @child AND b.parent_app_user_id = @owner
              AND c.status = 'active' AND p.status = 'active'
            """, conn);
        cmd.Parameters.AddWithValue("child", childId);
        cmd.Parameters.AddWithValue("owner", owner);
        return await cmd.ExecuteScalarAsync() as string;
    }

    public static async Task<object> Overview(string connectionString, string owner)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("""
            SELECT b.child_profile_key, a.score
            FROM child_user_bindings b
            LEFT JOIN child_credit_accounts a ON a.profile_key = b.child_profile_key
            WHERE b.parent_app_user_id = @owner
            """, conn);
        cmd.Parameters.AddWithValue("owner", owner);
        var rows = new List<object>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync()) rows.Add(new
        {
            profileKey = reader.GetString(0),
            creditEnabled = !reader.IsDBNull(1),
            creditScore = reader.IsDBNull(1) ? (int?)null : reader.GetInt32(1)
        });
        return new { children = rows };
    }

    public static async Task<object> Read(string connectionString, string key)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var scoreCmd = new NpgsqlCommand("SELECT score, version FROM child_credit_accounts WHERE profile_key = @key", conn);
        scoreCmd.Parameters.AddWithValue("key", key);
        int? score = null;
        long version = 0;
        await using (var reader = await scoreCmd.ExecuteReaderAsync())
            if (await reader.ReadAsync()) { score = reader.GetInt32(0); version = reader.GetInt64(1); }
        if (score is null) return new { enabled = false, score, version, commitments = Array.Empty<object>(), events = Array.Empty<object>(), disputes = Array.Empty<object>() };

        var commitments = new List<object>();
        await using (var cmd = new NpgsqlCommand("SELECT id,title,due_at,status,completion_requested_at,resolved_at,created_at FROM child_commitments WHERE profile_key=@key ORDER BY created_at DESC LIMIT 100", conn))
        {
            cmd.Parameters.AddWithValue("key", key);
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) commitments.Add(new
            {
                id = reader.GetInt64(0), title = reader.GetString(1), dueAt = reader.GetDateTime(2), status = reader.GetString(3),
                completionRequestedAt = reader.IsDBNull(4) ? (DateTime?)null : reader.GetDateTime(4),
                resolvedAt = reader.IsDBNull(5) ? (DateTime?)null : reader.GetDateTime(5), createdAt = reader.GetDateTime(6)
            });
        }
        var events = new List<object>();
        await using (var cmd = new NpgsqlCommand("SELECT id,commitment_id,reason_code,delta,score_before,score_after,note,actor_user_id,reversal_of_event_id,created_at FROM child_credit_events WHERE profile_key=@key ORDER BY id DESC LIMIT 100", conn))
        {
            cmd.Parameters.AddWithValue("key", key);
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) events.Add(new
            {
                id = reader.GetInt64(0), commitmentId = reader.IsDBNull(1) ? (long?)null : reader.GetInt64(1), reasonCode = reader.GetString(2),
                delta = reader.GetInt32(3), scoreBefore = reader.GetInt32(4), scoreAfter = reader.GetInt32(5), note = reader.GetString(6),
                actorUserId = reader.GetString(7), reversalOfEventId = reader.IsDBNull(8) ? (long?)null : reader.GetInt64(8), createdAt = reader.GetDateTime(9)
            });
        }
        var disputes = new List<object>();
        await using (var cmd = new NpgsqlCommand("SELECT id,event_id,reason,status,parent_response,created_at,resolved_at FROM child_credit_disputes WHERE profile_key=@key ORDER BY id DESC LIMIT 100", conn))
        {
            cmd.Parameters.AddWithValue("key", key);
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) disputes.Add(new
            {
                id = reader.GetInt64(0), eventId = reader.GetInt64(1), reason = reader.GetString(2), status = reader.GetString(3),
                parentResponse = reader.GetString(4), createdAt = reader.GetDateTime(5),
                resolvedAt = reader.IsDBNull(6) ? (DateTime?)null : reader.GetDateTime(6)
            });
        }
        return new { enabled = true, score, version, commitments, events, disputes };
    }

    public static async Task<IResult> Enable(string connectionString, string key, string owner)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await using var cmd = new NpgsqlCommand("INSERT INTO child_credit_accounts(profile_key,score) VALUES(@key,80) ON CONFLICT DO NOTHING RETURNING score", conn, tx);
        cmd.Parameters.AddWithValue("key", key);
        var inserted = await cmd.ExecuteScalarAsync();
        if (inserted is not null)
            await AddEvent(conn, tx, key, null, "opened", 80, 0, 80, "信用分已开通", owner, null, null);
        await tx.CommitAsync();
        return Results.Json(await Read(connectionString, key));
    }

    public static async Task<IResult> CreateCommitment(string connectionString, string key, string owner, JsonObject body)
    {
        var title = Text(body, "title");
        var id = RequestId(body);
        if (title.Length is < 2 or > 160 || id is null) return Bad("请输入 2–160 字的约定和有效请求编号");
        if (!DateTimeOffset.TryParse(Text(body, "dueAt"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var due)
            || due <= DateTimeOffset.UtcNow || due > DateTimeOffset.UtcNow.AddYears(1)) return Bad("请选择一年内的未来截止时间");
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO child_commitments(profile_key,owner_parent_app_user_id,title,due_at,request_id)
            SELECT @key,@owner,@title,@due,@id WHERE EXISTS(SELECT 1 FROM child_credit_accounts WHERE profile_key=@key)
            ON CONFLICT(profile_key,request_id) DO NOTHING RETURNING id
            """, conn);
        cmd.Parameters.AddWithValue("key", key); cmd.Parameters.AddWithValue("owner", owner);
        cmd.Parameters.AddWithValue("title", title); cmd.Parameters.AddWithValue("due", due.UtcDateTime); cmd.Parameters.AddWithValue("id", id.Value);
        var created = await cmd.ExecuteScalarAsync();
        if (created is null)
        {
            await using var exists = new NpgsqlCommand("SELECT 1 FROM child_credit_accounts WHERE profile_key=@key", conn);
            exists.Parameters.AddWithValue("key", key);
            if (await exists.ExecuteScalarAsync() is null) return Conflict("请先开通信用分");
        }
        return Results.Json(await Read(connectionString, key));
    }

    public static async Task<IResult> RequestCompletion(string connectionString, string key, long commitmentId)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("""
            UPDATE child_commitments SET status=CASE WHEN status='overdue' THEN 'late_pending' ELSE 'pending' END,
                completion_requested_at=CURRENT_TIMESTAMP
            WHERE id=@id AND profile_key=@key AND status IN ('open','overdue') RETURNING id
            """, conn);
        cmd.Parameters.AddWithValue("id", commitmentId); cmd.Parameters.AddWithValue("key", key);
        if (await cmd.ExecuteScalarAsync() is null) return Conflict("约定状态已变化，请刷新后重试");
        return Results.Json(await Read(connectionString, key));
    }

    public static async Task<IResult> ResolveCommitment(string connectionString, string key, string owner, long commitmentId, JsonObject body)
    {
        var action = Text(body, "action");
        if (action is not ("completed" or "overdue")) return Bad("请选择确认完成或确认逾期");
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        var score = await LockedScore(conn, tx, key);
        if (score is null) return Conflict("请先开通信用分");
        await using var cmd = new NpgsqlCommand("SELECT status,due_at,completion_requested_at FROM child_commitments WHERE id=@id AND profile_key=@key FOR UPDATE", conn, tx);
        cmd.Parameters.AddWithValue("id", commitmentId); cmd.Parameters.AddWithValue("key", key);
        string status; DateTime due; DateTime? requested;
        await using (var reader = await cmd.ExecuteReaderAsync())
        {
            if (!await reader.ReadAsync()) return Results.NotFound(new { error = "约定不存在" });
            status = reader.GetString(0); due = reader.GetDateTime(1);
            requested = reader.IsDBNull(2) ? null : reader.GetDateTime(2);
        }
        if (action == "completed" && status is not ("open" or "pending" or "late_pending")) return Conflict("此约定不能再确认完成");
        if (action == "overdue" && (status is not ("open" or "pending") || due > DateTime.UtcNow)) return Conflict("约定尚未到期或已处理");
        var nominal = action == "overdue" ? -2 : status == "late_pending" || (requested ?? DateTime.UtcNow) > due ? 1 : 2;
        var next = Math.Clamp(score.Value + nominal, 0, 100);
        var reason = action == "overdue" ? "commitment_overdue" : nominal == 1 ? "commitment_remedied" : "commitment_completed";
        await ApplyScore(conn, tx, key, next);
        await AddEvent(conn, tx, key, commitmentId, reason, next - score.Value, score.Value, next, Text(body, "note")[..Math.Min(Text(body, "note").Length, 500)], owner, null, null);
        await using var update = new NpgsqlCommand("UPDATE child_commitments SET status=@status,resolved_at=CURRENT_TIMESTAMP WHERE id=@id", conn, tx);
        update.Parameters.AddWithValue("status", action); update.Parameters.AddWithValue("id", commitmentId);
        await update.ExecuteNonQueryAsync();
        await tx.CommitAsync();
        return Results.Json(await Read(connectionString, key));
    }

    public static async Task<IResult> Adjust(string connectionString, string key, string owner, JsonObject body)
    {
        var reason = Text(body, "reasonCode");
        var note = Text(body, "note");
        var id = RequestId(body);
        if (id is null || !int.TryParse(Text(body, "delta"), out var delta) || note.Length > 500) return Bad("调整参数无效");
        if (reason is "honesty" or "responsibility") { if (delta is < 1 or > 3) return Bad("该原因每次可加 1–3 分"); }
        else if (reason == "false_report") { if (delta != -5 || note.Length < 2) return Bad("虚报完成须填写说明并扣 5 分"); }
        else if (reason == "adjustment") { if (delta is < -5 or > 5 || delta == 0 || note.Length < 2) return Bad("手工调整须填写说明，范围为 ±1–5 分"); }
        else return Bad("调整原因无效");
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        var score = await LockedScore(conn, tx, key);
        if (score is null) return Conflict("请先开通信用分");
        await using (var duplicate = new NpgsqlCommand("SELECT 1 FROM child_credit_events WHERE profile_key=@key AND request_id=@id", conn, tx))
        {
            duplicate.Parameters.AddWithValue("key", key); duplicate.Parameters.AddWithValue("id", id.Value);
            if (await duplicate.ExecuteScalarAsync() is not null)
            {
                await tx.RollbackAsync();
                return Results.Json(await Read(connectionString, key));
            }
        }
        await using (var limit = new NpgsqlCommand("""
            SELECT COALESCE(SUM(ABS(delta)),0), COUNT(*) FILTER(WHERE reason_code=@reason)
            FROM child_credit_events WHERE profile_key=@key AND actor_user_id=@owner
              AND reason_code IN ('honesty','responsibility','false_report','adjustment')
              AND (created_at AT TIME ZONE 'Asia/Shanghai')::date=(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai')::date
            """, conn, tx))
        {
            limit.Parameters.AddWithValue("key", key); limit.Parameters.AddWithValue("owner", owner); limit.Parameters.AddWithValue("reason", reason);
            await using var reader = await limit.ExecuteReaderAsync();
            await reader.ReadAsync();
            if (reader.GetInt64(0) + Math.Abs(delta) > 10 || reader.GetInt64(1) > 0) return Conflict("今日同类调整已记录，或手工调整已达 10 分上限");
        }
        var next = score.Value + delta;
        if (next is < 0 or > 100) return Conflict("调整后信用分必须在 0–100 分之间");
        await ApplyScore(conn, tx, key, next);
        await AddEvent(conn, tx, key, null, reason, delta, score.Value, next, note, owner, id, null);
        await tx.CommitAsync();
        return Results.Json(await Read(connectionString, key));
    }

    public static async Task<IResult> Reverse(string connectionString, string key, string owner, long eventId, JsonObject body)
    {
        var note = Text(body, "note");
        if (note.Length is < 2 or > 500) return Bad("请填写 2–500 字的撤销原因");
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        var result = await ReverseEvent(conn, tx, key, owner, eventId, note);
        if (result is not null) return result;
        await tx.CommitAsync();
        return Results.Json(await Read(connectionString, key));
    }

    public static async Task<IResult> Dispute(string connectionString, string key, long eventId, JsonObject body)
    {
        var reason = Text(body, "reason");
        if (reason.Length is < 2 or > 500) return Bad("请填写 2–500 字的异议说明");
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO child_credit_disputes(profile_key,event_id,reason)
            SELECT @key,e.id,@reason FROM child_credit_events e
            WHERE e.id=@id AND e.profile_key=@key AND e.delta<0 AND e.reversal_of_event_id IS NULL
              AND NOT EXISTS(SELECT 1 FROM child_credit_events r WHERE r.reversal_of_event_id=e.id)
            ON CONFLICT(event_id) DO NOTHING RETURNING id
            """, conn);
        cmd.Parameters.AddWithValue("key", key); cmd.Parameters.AddWithValue("id", eventId); cmd.Parameters.AddWithValue("reason", reason);
        if (await cmd.ExecuteScalarAsync() is null) return Conflict("该记录无法提交异议，或异议已提交");
        return Results.Json(await Read(connectionString, key));
    }

    public static async Task<IResult> ResolveDispute(string connectionString, string key, string owner, long disputeId, JsonObject body)
    {
        var action = Text(body, "action");
        var response = Text(body, "response");
        if (action is not ("accepted" or "rejected") || response.Length is < 2 or > 500) return Bad("请选择处理结果并填写说明");
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();
        if (await LockedScore(conn, tx, key) is null) return Conflict("信用分尚未开通");
        await using var cmd = new NpgsqlCommand("SELECT event_id,status FROM child_credit_disputes WHERE id=@id AND profile_key=@key FOR UPDATE", conn, tx);
        cmd.Parameters.AddWithValue("id", disputeId); cmd.Parameters.AddWithValue("key", key);
        long eventId; string status;
        await using (var reader = await cmd.ExecuteReaderAsync())
        {
            if (!await reader.ReadAsync()) return Results.NotFound(new { error = "异议不存在" });
            eventId = reader.GetInt64(0); status = reader.GetString(1);
        }
        if (status != "pending") return Conflict("异议已处理");
        if (action == "accepted")
        {
            var result = await ReverseEvent(conn, tx, key, owner, eventId, response);
            if (result is not null) return result;
        }
        await using var update = new NpgsqlCommand("UPDATE child_credit_disputes SET status=@action,parent_response=@response,resolved_at=CURRENT_TIMESTAMP WHERE id=@id", conn, tx);
        update.Parameters.AddWithValue("action", action); update.Parameters.AddWithValue("response", response); update.Parameters.AddWithValue("id", disputeId);
        await update.ExecuteNonQueryAsync();
        await tx.CommitAsync();
        return Results.Json(await Read(connectionString, key));
    }

    private static async Task<IResult?> ReverseEvent(NpgsqlConnection conn, NpgsqlTransaction tx, string key, string owner, long eventId, string note)
    {
        var score = await LockedScore(conn, tx, key);
        if (score is null) return Conflict("信用分尚未开通");
        await using var cmd = new NpgsqlCommand("SELECT delta,reason_code,commitment_id,reversal_of_event_id FROM child_credit_events WHERE id=@id AND profile_key=@key FOR UPDATE", conn, tx);
        cmd.Parameters.AddWithValue("id", eventId); cmd.Parameters.AddWithValue("key", key);
        int delta; string reason; long? commitmentId; bool reversed;
        await using (var reader = await cmd.ExecuteReaderAsync())
        {
            if (!await reader.ReadAsync()) return Results.NotFound(new { error = "记录不存在" });
            delta = reader.GetInt32(0); reason = reader.GetString(1);
            commitmentId = reader.IsDBNull(2) ? null : reader.GetInt64(2); reversed = !reader.IsDBNull(3);
        }
        if (reason == "opened" || reversed) return Conflict("此记录不能撤销");
        if (commitmentId is not null)
        {
            await using var later = new NpgsqlCommand("SELECT 1 FROM child_credit_events WHERE commitment_id=@commitment AND id>@id AND reason_code<>'reversal' LIMIT 1", conn, tx);
            later.Parameters.AddWithValue("commitment", commitmentId.Value); later.Parameters.AddWithValue("id", eventId);
            if (await later.ExecuteScalarAsync() is not null) return Conflict("该约定有后续处理记录，请先处理后续记录");
        }
        await using (var exists = new NpgsqlCommand("SELECT 1 FROM child_credit_events WHERE reversal_of_event_id=@id", conn, tx))
        {
            exists.Parameters.AddWithValue("id", eventId);
            if (await exists.ExecuteScalarAsync() is not null) return Conflict("此记录已撤销");
        }
        var next = score.Value - delta;
        if (next is < 0 or > 100) return Conflict("当前分值无法完整撤销该笔变更，请先处理后续记录");
        await ApplyScore(conn, tx, key, next);
        await AddEvent(conn, tx, key, commitmentId, "reversal", -delta, score.Value, next, note, owner, null, eventId);
        if (commitmentId is not null)
        {
            await using var update = new NpgsqlCommand("UPDATE child_commitments SET status='open',resolved_at=NULL,completion_requested_at=NULL WHERE id=@id", conn, tx);
            update.Parameters.AddWithValue("id", commitmentId.Value);
            await update.ExecuteNonQueryAsync();
        }
        return null;
    }

    private static async Task<int?> LockedScore(NpgsqlConnection conn, NpgsqlTransaction tx, string key)
    {
        await using var cmd = new NpgsqlCommand("SELECT score FROM child_credit_accounts WHERE profile_key=@key FOR UPDATE", conn, tx);
        cmd.Parameters.AddWithValue("key", key);
        return await cmd.ExecuteScalarAsync() is int score ? score : null;
    }

    private static async Task ApplyScore(NpgsqlConnection conn, NpgsqlTransaction tx, string key, int score)
    {
        await using var cmd = new NpgsqlCommand("UPDATE child_credit_accounts SET score=@score,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE profile_key=@key", conn, tx);
        cmd.Parameters.AddWithValue("key", key); cmd.Parameters.AddWithValue("score", score);
        await cmd.ExecuteNonQueryAsync();
    }

    private static async Task AddEvent(NpgsqlConnection conn, NpgsqlTransaction tx, string key, long? commitmentId, string reason,
        int delta, int before, int after, string note, string actor, Guid? requestId, long? reversedId)
    {
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO child_credit_events(profile_key,commitment_id,reason_code,delta,score_before,score_after,note,actor_user_id,request_id,reversal_of_event_id)
            VALUES(@key,@commitment,@reason,@delta,@before,@after,@note,@actor,@request,@reversed)
            """, conn, tx);
        cmd.Parameters.AddWithValue("key", key); cmd.Parameters.Add("commitment", NpgsqlDbType.Bigint).Value = (object?)commitmentId ?? DBNull.Value;
        cmd.Parameters.AddWithValue("reason", reason); cmd.Parameters.AddWithValue("delta", delta);
        cmd.Parameters.AddWithValue("before", before); cmd.Parameters.AddWithValue("after", after);
        cmd.Parameters.AddWithValue("note", note); cmd.Parameters.AddWithValue("actor", actor);
        cmd.Parameters.Add("request", NpgsqlDbType.Uuid).Value = (object?)requestId ?? DBNull.Value;
        cmd.Parameters.Add("reversed", NpgsqlDbType.Bigint).Value = (object?)reversedId ?? DBNull.Value;
        await cmd.ExecuteNonQueryAsync();
    }
}
