using System.Text.Json.Nodes;
using Npgsql;

internal static class DiningCircleEndpoints
{
    private const string Mutual = """
        EXISTS (SELECT 1 FROM dining_buddy_consents a
            JOIN dining_buddy_consents b ON b.owner_id=a.buddy_id AND b.buddy_id=a.owner_id
            WHERE a.owner_id=@owner AND a.buddy_id=p.author_id)
        """;
    private const string Visible = "p.author_id=@owner OR (" + Mutual +
        " AND (p.visibility='buddies' OR (p.visibility='selected' AND @owner=ANY(p.selected_buddy_ids))))";
    private sealed record PostInput(Guid Id, string RestaurantId, string RestaurantName, string? Note, string? Visibility, string[]? BuddyIds);
    private sealed record PermissionInput(string Visibility, string[]? BuddyIds);
    private sealed record CommentInput(Guid Id, string Body);
    private sealed record ActionInput(bool Enabled);
    private sealed record InvitationInput(Guid GatheringId, string BuddyId);
    private sealed record ReplyInput(bool Accept);

    public static void MapDiningCircle(this WebApplication app, string cs, Func<HttpRequest, string?> ownerFor)
    {
        var group = app.MapGroup("/api/dining/circle").RequireAuthorization();
        group.AddEndpointFilter(async (context, next) =>
        {
            context.HttpContext.Response.Headers.CacheControl = "private, no-store";
            return ownerFor(context.HttpContext.Request) is null ? Results.Unauthorized() : await next(context);
        });

        group.MapGet("/buddies", (HttpRequest r, CancellationToken ct) => Read(cs, ownerFor(r)!, """
            SELECT jsonb_build_object('userId', other.user_id, 'sharedCount', count(*),
                'lastMealAt', max(g.ended_at),
                'mealIds', (array_agg(g.id ORDER BY g.ended_at DESC))[1:20],
                'outgoing', EXISTS(SELECT 1 FROM dining_buddy_consents c WHERE c.owner_id=@owner AND c.buddy_id=other.user_id),
                'incoming', EXISTS(SELECT 1 FROM dining_buddy_consents c WHERE c.owner_id=other.user_id AND c.buddy_id=@owner))::text
            FROM dining_gathering_members mine
            JOIN dining_gathering_members other USING(gathering_id)
            JOIN dining_gatherings g ON g.id=mine.gathering_id
            WHERE mine.user_id=@owner AND other.user_id<>@owner
                AND mine.confirmed_at IS NOT NULL AND other.confirmed_at IS NOT NULL AND g.ended_at IS NOT NULL
            GROUP BY other.user_id ORDER BY count(*) DESC, max(g.ended_at) DESC LIMIT 100
            """, ct));

        group.MapPut("/buddies/{buddy}", async (string buddy, ActionInput input, HttpRequest r, CancellationToken ct) =>
        {
            var owner = ownerFor(r)!;
            buddy = Normalize(buddy);
            if (buddy == owner || buddy.Length is 0 or > 256) return Results.BadRequest();
            var sql = input.Enabled ? """
                INSERT INTO dining_buddy_consents(owner_id,buddy_id)
                SELECT @owner,@buddy WHERE EXISTS (
                    SELECT 1 FROM dining_gathering_members mine
                    JOIN dining_gathering_members other USING(gathering_id)
                    JOIN dining_gatherings g ON g.id=mine.gathering_id
                    WHERE mine.user_id=@owner AND other.user_id=@buddy AND g.ended_at IS NOT NULL
                        AND mine.confirmed_at IS NOT NULL AND other.confirmed_at IS NOT NULL)
                ON CONFLICT DO NOTHING
                """ : "DELETE FROM dining_buddy_consents WHERE owner_id=@owner AND buddy_id=@buddy";
            await Execute(cs, owner, sql, ct, ("buddy", buddy));
            return Results.NoContent();
        });

        group.MapGet("/posts", (HttpRequest r, CancellationToken ct) => Read(cs, ownerFor(r)!, """
            SELECT jsonb_build_object('id',p.id,'isMine',p.author_id=@owner,'authorId',p.author_id,
                'restaurantId',p.restaurant_id,'restaurantName',p.restaurant_name,'note',p.note,
                'visibility',p.visibility,'createdAt',p.created_at,
                'selectedBuddyIds', CASE WHEN p.author_id=@owner THEN p.selected_buddy_ids END,
                'comments', ARRAY(SELECT c.body FROM dining_circle_comments c WHERE c.post_id=p.id
                    ORDER BY c.created_at DESC LIMIT 20),
                'likes', (SELECT count(*) FROM dining_circle_actions a WHERE a.post_id=p.id AND a.kind='like'),
                'myActions', ARRAY(SELECT a.kind FROM dining_circle_actions a WHERE a.post_id=p.id AND a.user_id=@owner))::text
            FROM dining_circle_posts p WHERE
            """ + " (" + Visible + ") ORDER BY p.created_at DESC LIMIT 100", ct));

        group.MapGet("/restaurants", (HttpRequest r, CancellationToken ct) => Read(cs, ownerFor(r)!, """
            SELECT jsonb_build_object('restaurantId',p.restaurant_id,'restaurantName',max(p.restaurant_name),
                'saved',bool_or(a.kind='save'),'wanted',bool_or(a.kind='want'))::text
            FROM dining_circle_actions a JOIN dining_circle_posts p ON p.id=a.post_id
            WHERE a.user_id=@owner AND a.kind IN ('save','want') AND
            """ + " (" + Visible + ") GROUP BY p.restaurant_id ORDER BY max(p.created_at) DESC LIMIT 100", ct));

        group.MapPost("/posts", async (PostInput input, HttpRequest r, CancellationToken ct) =>
        {
            if (input.Id == Guid.Empty || input.RestaurantId is not { Length: > 0 and <= 256 } ||
                input.RestaurantName is not { Length: > 0 and <= 160 } || input.Note?.Length > 1000 ||
                !ValidPermission(input.Visibility ?? "private", input.BuddyIds)) return Results.BadRequest();
            var count = await Execute(cs, ownerFor(r)!, """
                INSERT INTO dining_circle_posts(id,author_id,restaurant_id,restaurant_name,note,visibility,selected_buddy_ids)
                VALUES(@id,@owner,@restaurant,@name,@note,@scope,@buddies)
                ON CONFLICT(id) DO UPDATE SET id=dining_circle_posts.id
                WHERE dining_circle_posts.author_id=@owner AND dining_circle_posts.restaurant_id=@restaurant
                    AND dining_circle_posts.restaurant_name=@name AND dining_circle_posts.note=@note
                    AND dining_circle_posts.visibility=@scope AND dining_circle_posts.selected_buddy_ids=@buddies
                """, ct, ("id",input.Id), ("restaurant",input.RestaurantId), ("name",input.RestaurantName),
                ("note",input.Note ?? ""), ("scope",input.Visibility ?? "private"), ("buddies", BuddyIds(input.BuddyIds)));
            return count == 0 ? Results.Conflict() : Results.Ok(new { id = input.Id });
        });

        group.MapPut("/posts/{id:guid}/visibility", async (Guid id, PermissionInput input, HttpRequest r, CancellationToken ct) =>
        {
            if (!ValidPermission(input.Visibility, input.BuddyIds)) return Results.BadRequest();
            var count = await Execute(cs, ownerFor(r)!, """
                UPDATE dining_circle_posts SET visibility=@scope,selected_buddy_ids=@buddies WHERE id=@id AND author_id=@owner
                """, ct, ("id",id), ("scope",input.Visibility), ("buddies",BuddyIds(input.BuddyIds)));
            return count == 0 ? Results.NotFound() : Results.NoContent();
        });

        group.MapDelete("/posts/{id:guid}", async (Guid id, HttpRequest r, CancellationToken ct) =>
        {
            await Execute(cs, ownerFor(r)!, "DELETE FROM dining_circle_posts WHERE id=@id AND author_id=@owner", ct, ("id",id));
            return Results.NoContent();
        });

        group.MapPut("/posts/{id:guid}/actions/{kind}", async (Guid id, string kind, ActionInput input, HttpRequest r, CancellationToken ct) =>
        {
            if (kind is not ("like" or "save" or "want")) return Results.BadRequest();
            var sql = input.Enabled
                ? "INSERT INTO dining_circle_actions(post_id,user_id,kind) SELECT p.id,@owner,@kind FROM dining_circle_posts p WHERE p.id=@id AND (" + Visible + ") ON CONFLICT DO NOTHING"
                : "DELETE FROM dining_circle_actions WHERE post_id=@id AND user_id=@owner AND kind=@kind";
            await Execute(cs, ownerFor(r)!, sql, ct, ("id",id), ("kind",kind));
            return Results.NoContent();
        });

        group.MapPost("/posts/{id:guid}/comments", async (Guid id, CommentInput input, HttpRequest r, CancellationToken ct) =>
        {
            var body = input.Body?.Trim();
            if (input.Id == Guid.Empty || body is not { Length: > 0 and <= 500 }) return Results.BadRequest();
            var count = await Execute(cs, ownerFor(r)!, """
                INSERT INTO dining_circle_comments(id,post_id,author_id,body)
                SELECT @comment,p.id,@owner,@body FROM dining_circle_posts p WHERE p.id=@id AND
                """ + " (" + Visible + ") " + """
                ON CONFLICT(id) DO UPDATE SET id=dining_circle_comments.id
                WHERE dining_circle_comments.post_id=@id AND dining_circle_comments.author_id=@owner
                    AND dining_circle_comments.body=@body
                """, ct, ("id",id), ("comment",input.Id), ("body",body));
            return count == 0 ? Results.NotFound() : Results.NoContent();
        });

        group.MapGet("/invitations", (HttpRequest r, CancellationToken ct) => Read(cs, ownerFor(r)!, """
            SELECT jsonb_build_object('gatheringId',g.id,'restaurantName',g.restaurant_name,'inviterId',i.inviter_id,
                'status',i.status,'endedAt',g.ended_at)::text
            FROM dining_gathering_invitations i JOIN dining_gatherings g ON g.id=i.gathering_id
            WHERE i.invitee_id=@owner ORDER BY i.created_at DESC LIMIT 100
            """, ct));
        group.MapPost("/invitations", async (InvitationInput input, HttpRequest r, CancellationToken ct) =>
        {
            var buddy = Normalize(input.BuddyId ?? "");
            if (buddy.Length is 0 or > 256) return Results.BadRequest();
            var count = await Execute(cs, ownerFor(r)!, """
                INSERT INTO dining_gathering_invitations(gathering_id,inviter_id,invitee_id)
                SELECT g.id,@owner,@buddy FROM dining_gatherings g
                JOIN dining_buddy_consents a ON a.owner_id=@owner AND a.buddy_id=@buddy
                JOIN dining_buddy_consents b ON b.owner_id=@buddy AND b.buddy_id=@owner
                WHERE g.id=@id AND g.host_id=@owner AND g.ended_at IS NULL
                    AND g.created_at > now()-interval '24 hours'
                ON CONFLICT (gathering_id,invitee_id) DO UPDATE SET inviter_id=EXCLUDED.inviter_id
                """, ct, ("id",input.GatheringId), ("buddy",buddy));
            return count == 0 ? Results.NotFound() : Results.NoContent();
        });

        group.MapPut("/invitations/{id:guid}", (Guid id, ReplyInput input, HttpRequest r, CancellationToken ct) =>
            Reply(cs, id, ownerFor(r)!, input.Accept, ct));
    }

    private static async Task<IResult> Reply(string cs, Guid id, string owner, bool accept, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var tx = await db.BeginTransactionAsync(ct);
        await using var read = new NpgsqlCommand("""
            SELECT i.status, g.ended_at IS NULL AND g.created_at > now()-interval '24 hours'
                AND EXISTS (SELECT 1 FROM dining_buddy_consents a JOIN dining_buddy_consents b
                    ON b.owner_id=a.buddy_id AND b.buddy_id=a.owner_id
                    WHERE a.owner_id=i.inviter_id AND a.buddy_id=i.invitee_id)
            FROM dining_gathering_invitations i JOIN dining_gatherings g ON g.id=i.gathering_id
            WHERE i.invitee_id=@owner AND g.id=@id FOR UPDATE OF g,i
            """, db, tx);
        read.Parameters.AddWithValue("owner", owner);
        read.Parameters.AddWithValue("id", id);
        var status = accept ? "accepted" : "declined";
        await using (var row = await read.ExecuteReaderAsync(ct))
        {
            if (!await row.ReadAsync(ct)) return Results.NotFound();
            if (row.GetString(0) == status) return Results.NoContent();
            if (row.GetString(0) != "pending" || (accept && !row.GetBoolean(1))) return Results.Conflict();
        }
        if (accept)
        {
            await using var join = new NpgsqlCommand("""
                INSERT INTO dining_gathering_members(gathering_id,user_id) VALUES(@id,@owner) ON CONFLICT DO NOTHING
                """, db, tx);
            join.Parameters.AddWithValue("id",id);
            join.Parameters.AddWithValue("owner",owner);
            await join.ExecuteNonQueryAsync(ct);
        }
        await using var update = new NpgsqlCommand("""
            UPDATE dining_gathering_invitations SET status=@status WHERE gathering_id=@id AND invitee_id=@owner
            """, db, tx);
        update.Parameters.AddWithValue("id",id);
        update.Parameters.AddWithValue("owner",owner);
        update.Parameters.AddWithValue("status",status);
        await update.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        return Results.NoContent();
    }

    private static bool ValidPermission(string? scope, string[]? buddies) =>
        scope is "private" or "buddies" or "selected" &&
        (buddies is null || buddies.Length <= 50 && buddies.All(x => x is { Length: > 0 and <= 256 })) &&
        (scope == "selected" ? buddies is { Length: > 0 } : buddies is null or { Length: 0 });
    private static string Normalize(string value) => Guid.TryParse(value, out var id) ? id.ToString("D") : value;
    private static string[] BuddyIds(string[]? values) => values?.Select(Normalize).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray() ?? [];

    private static async Task<int> Execute(string cs, string owner, string sql, CancellationToken ct, params (string Key, object Value)[] args)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, db);
        command.Parameters.AddWithValue("owner", owner);
        foreach (var (key,value) in args) command.Parameters.AddWithValue(key,value);
        return await command.ExecuteNonQueryAsync(ct);
    }

    private static async Task<IResult> Read(string cs, string owner, string sql, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, db);
        command.Parameters.AddWithValue("owner", owner);
        await using var rows = await command.ExecuteReaderAsync(ct);
        var result = new JsonArray();
        while (await rows.ReadAsync(ct)) result.Add(JsonNode.Parse(rows.GetString(0)));
        return Results.Json(result);
    }
}
