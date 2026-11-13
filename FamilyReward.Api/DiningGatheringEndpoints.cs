using System.Security.Cryptography;
using System.Globalization;
using Npgsql;

internal static class DiningGatheringEndpoints
{
    private sealed record CreateGathering(Guid Id, string RestaurantId, string RestaurantName);
    private sealed record JoinGathering(string Code);

    public static void MapDiningGatherings(this WebApplication app, string connectionString, Func<HttpRequest, string?> ownerFor)
    {
        var group = app.MapGroup("/api/dining/gatherings").RequireAuthorization();
        group.AddEndpointFilter(async (context, next) =>
        {
            context.HttpContext.Response.Headers.CacheControl = "private, no-store";
            return ownerFor(context.HttpContext.Request) is null ? Results.Unauthorized() : await next(context);
        });

        group.MapPost("", async (CreateGathering input, HttpRequest request, CancellationToken ct) =>
        {
            var restaurantId = input.RestaurantId?.Trim();
            var restaurantName = input.RestaurantName?.Trim();
            if (input.Id == Guid.Empty || restaurantId is not { Length: > 0 and <= 256 } ||
                restaurantName is not { Length: > 0 and <= 160 }) return Results.BadRequest();
            var owner = ownerFor(request)!;
            await using var db = new NpgsqlConnection(connectionString);
            await db.OpenAsync(ct);
            await using var tx = await db.BeginTransactionAsync(ct);
            await using var create = new NpgsqlCommand("""
                INSERT INTO dining_gatherings(id,host_id,join_code,restaurant_id,restaurant_name)
                VALUES (@id,@owner,@code,@restaurant,@name)
                ON CONFLICT (id) DO NOTHING
                """, db, tx);
            create.Parameters.AddWithValue("id", input.Id);
            create.Parameters.AddWithValue("owner", owner);
            create.Parameters.AddWithValue("code", Guid.NewGuid());
            create.Parameters.AddWithValue("restaurant", restaurantId);
            create.Parameters.AddWithValue("name", restaurantName);
            var created = await create.ExecuteNonQueryAsync(ct) == 1;
            await using var verify = new NpgsqlCommand("""
                SELECT 1 FROM dining_gatherings WHERE id=@id AND host_id=@owner
                    AND restaurant_id=@restaurant AND restaurant_name=@name
                """, db, tx);
            verify.Parameters.AddWithValue("id", input.Id);
            verify.Parameters.AddWithValue("owner", owner);
            verify.Parameters.AddWithValue("restaurant", restaurantId);
            verify.Parameters.AddWithValue("name", restaurantName);
            if (await verify.ExecuteScalarAsync(ct) is null) return Results.Conflict();
            if (created && !await AllocateCode(db, tx, input.Id, ct)) return Results.StatusCode(503);
            await AddMember(db, tx, input.Id, owner, ct);
            await tx.CommitAsync(ct);
            return Results.Ok(new { id = input.Id });
        });

        group.MapPost("/join", async (JoinGathering input, HttpRequest request, CancellationToken ct) =>
        {
            var code = input.Code?.Trim() ?? "";
            var numeric = code.Length == 6 && code.All(char.IsAsciiDigit);
            var legacy = Guid.TryParseExact(code, "D", out var legacyCode) && legacyCode != Guid.Empty;
            if (!numeric && !legacy) return Results.BadRequest();
            var owner = ownerFor(request)!;
            await using var db = new NpgsqlConnection(connectionString);
            await db.OpenAsync(ct);
            if (numeric && !await AllowCodeAttempt(db, owner, ct)) return Results.StatusCode(429);
            await using var tx = await db.BeginTransactionAsync(ct);
            await using var lookup = new NpgsqlCommand("""
                SELECT g.id FROM dining_gatherings g
                WHERE g.ended_at IS NULL AND g.created_at > clock_timestamp() - interval '20 minutes'
                AND (g.join_code=@legacy OR EXISTS (
                    SELECT 1 FROM dining_short_codes c WHERE c.gathering_id=g.id AND c.code=@code
                    AND c.expires_at > clock_timestamp()))
                FOR UPDATE OF g
                """, db, tx);
            lookup.Parameters.AddWithValue("legacy", NpgsqlTypes.NpgsqlDbType.Uuid, legacy ? legacyCode : DBNull.Value);
            lookup.Parameters.AddWithValue("code", code);
            if (await lookup.ExecuteScalarAsync(ct) is not Guid id)
                return Results.NotFound(new { error = "口令无效或已过期。" });
            await AddMember(db, tx, id, owner, ct);
            await tx.CommitAsync(ct);
            return Results.Ok(new { id });
        });

        group.MapGet("", (HttpRequest request, CancellationToken ct) =>
            Read(connectionString, ownerFor(request)!, null, ct));
        group.MapGet("/{id:guid}", (Guid id, HttpRequest request, CancellationToken ct) =>
            Read(connectionString, ownerFor(request)!, id, ct));
        group.MapPost("/{id:guid}/confirm", (Guid id, HttpRequest request, CancellationToken ct) =>
            Transition(connectionString, id, ownerFor(request)!, false, ct));
        group.MapPost("/{id:guid}/end", (Guid id, HttpRequest request, CancellationToken ct) =>
            Transition(connectionString, id, ownerFor(request)!, true, ct));
    }

    private static async Task<bool> AllocateCode(NpgsqlConnection db, NpgsqlTransaction tx, Guid id, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand("""
            INSERT INTO dining_short_codes(code,gathering_id,expires_at)
            SELECT @code,id,created_at + interval '20 minutes' FROM dining_gatherings WHERE id=@id
            ON CONFLICT (code) DO UPDATE SET gathering_id=EXCLUDED.gathering_id,expires_at=EXCLUDED.expires_at
            WHERE dining_short_codes.expires_at <= clock_timestamp()
            """, db, tx);
        command.Parameters.AddWithValue("id", id);
        var code = command.Parameters.Add("code", NpgsqlTypes.NpgsqlDbType.Text);
        for (var attempt = 0; attempt < 12; attempt++)
        {
            code.Value = RandomNumberGenerator.GetInt32(1_000_000).ToString("D6", CultureInfo.InvariantCulture);
            if (await command.ExecuteNonQueryAsync(ct) == 1) return true;
        }
        return false;
    }

    private static async Task<bool> AllowCodeAttempt(NpgsqlConnection db, string owner, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand("""
            INSERT INTO dining_code_attempts(owner_id,window_start,attempts) VALUES(@owner,now(),1)
            ON CONFLICT(owner_id) DO UPDATE SET
                window_start=CASE WHEN dining_code_attempts.window_start <= now()-interval '1 minute'
                    THEN now() ELSE dining_code_attempts.window_start END,
                attempts=CASE WHEN dining_code_attempts.window_start <= now()-interval '1 minute'
                    THEN 1 ELSE dining_code_attempts.attempts+1 END
            WHERE dining_code_attempts.window_start <= now()-interval '1 minute' OR dining_code_attempts.attempts < 8
            """, db);
        command.Parameters.AddWithValue("owner", owner);
        return await command.ExecuteNonQueryAsync(ct) == 1;
    }

    private static async Task AddMember(NpgsqlConnection db, NpgsqlTransaction tx, Guid id, string owner, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand("""
            INSERT INTO dining_gathering_members(gathering_id,user_id)
            VALUES (@id,@owner) ON CONFLICT DO NOTHING
            """, db, tx);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("owner", owner);
        await command.ExecuteNonQueryAsync(ct);
    }

    private static async Task<IResult> Read(string cs, string owner, Guid? id, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var query = new NpgsqlCommand("""
            SELECT jsonb_build_object(
                'id',g.id,'isHost',g.host_id=@owner,'restaurantName',g.restaurant_name,
                'restaurantId',g.restaurant_id,'createdAt',g.created_at,'endedAt',g.ended_at,
                'joinExpired',g.created_at <= now() - interval '20 minutes',
                'joinCode',CASE WHEN g.host_id=@owner AND g.ended_at IS NULL AND
                    g.created_at > now() - interval '20 minutes' THEN g.join_code END,
                'shortCode',CASE WHEN g.host_id=@owner AND g.ended_at IS NULL
                    AND g.created_at > clock_timestamp() - interval '20 minutes'
                    AND c.expires_at > clock_timestamp() THEN c.code END,
                'codeExpiresAt',CASE WHEN g.host_id=@owner AND g.ended_at IS NULL THEN c.expires_at END,
                'myConfirmedAt',mine.confirmed_at,
                'members',(SELECT jsonb_agg(jsonb_build_object(
                    'userId',m.user_id,'confirmedAt',m.confirmed_at) ORDER BY m.joined_at,m.user_id)
                    FROM dining_gathering_members m WHERE m.gathering_id=g.id)
            )::text
            FROM dining_gathering_members mine
            JOIN dining_gatherings g ON g.id=mine.gathering_id
            LEFT JOIN dining_short_codes c ON c.gathering_id=g.id
            WHERE mine.user_id=@owner AND (@id IS NULL OR g.id=@id)
            ORDER BY g.created_at DESC LIMIT 100
            """, db);
        query.Parameters.AddWithValue("owner", owner);
        query.Parameters.AddWithValue("id", NpgsqlTypes.NpgsqlDbType.Uuid, (object?)id ?? DBNull.Value);
        await using var rows = await query.ExecuteReaderAsync(ct);
        var items = new System.Text.Json.Nodes.JsonArray();
        while (await rows.ReadAsync(ct)) items.Add(System.Text.Json.Nodes.JsonNode.Parse(rows.GetString(0)));
        if (id is null) return Results.Json(items);
        return items.Count == 0 ? Results.NotFound() : Results.Json(items[0]);
    }

    private static async Task<IResult> Transition(string cs, Guid id, string owner, bool end, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var tx = await db.BeginTransactionAsync(ct);
        await using var lookup = new NpgsqlCommand("""
            SELECT g.host_id,g.ended_at IS NOT NULL,m.confirmed_at IS NOT NULL
            FROM dining_gatherings g JOIN dining_gathering_members m ON m.gathering_id=g.id
            WHERE g.id=@id AND m.user_id=@owner FOR UPDATE OF g
            """, db, tx);
        lookup.Parameters.AddWithValue("id", id);
        lookup.Parameters.AddWithValue("owner", owner);
        await using (var row = await lookup.ExecuteReaderAsync(ct))
        {
            if (!await row.ReadAsync(ct) || (end && row.GetString(0) != owner)) return Results.NotFound();
            if (end ? row.GetBoolean(1) : row.GetBoolean(2)) return Results.NoContent();
            if (row.GetBoolean(1)) return Results.Conflict();
        }
        await using var change = new NpgsqlCommand(end
            ? "UPDATE dining_gatherings SET ended_at=now() WHERE id=@id"
            : "UPDATE dining_gathering_members SET confirmed_at=now() WHERE gathering_id=@id AND user_id=@owner", db, tx);
        change.Parameters.AddWithValue("id", id);
        change.Parameters.AddWithValue("owner", owner);
        await change.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        return Results.NoContent();
    }
}
