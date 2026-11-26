using System.Globalization;
using System.Text;
using System.Text.Json;
using Npgsql;

internal static class BeverageEndpoints
{
    internal sealed record BeverageDraft(
        string Name, string? Brand, string Category, string? Kind,
        string? Origin, string? Producer, decimal? AlcoholPercent, int? Vintage, string? Size);
    internal sealed record ConsumptionDraft(
        Guid? BeverageId, BeverageDraft? Beverage, DateOnly ConsumedOn,
        int? Rating, string? Note, string? Place, Guid[]? PhotoIds);
    internal sealed record FavoriteDraft(bool Favorite);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static void MapBeverages(this WebApplication app, string connectionString, Func<HttpRequest, string?> owner)
    {
        var group = app.MapGroup("/api/beverages").RequireAuthorization();
        group.MapGet("/", async (HttpRequest request, CancellationToken ct) =>
        {
            if (owner(request) is not { } subject) return Results.Forbid();
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(ct);
            await using var command = new NpgsqlCommand("""
                SELECT jsonb_build_object('items', COALESCE(jsonb_agg(
                    p.body || jsonb_build_object('id',p.id,'favorite',p.favorite,'records',(
                       SELECT COALESCE(jsonb_agg(c.body || jsonb_build_object('id', c.id)
                               ORDER BY c.consumed_on DESC,c.id),'[]'::jsonb)
                       FROM beverage_consumptions c WHERE c.owner_id=p.owner_id AND c.beverage_id=p.id
                    )) ORDER BY p.body->>'name',p.id),'[]'::jsonb))::text
                FROM beverage_profiles p WHERE p.owner_id=@owner
                """, connection);
            command.Parameters.AddWithValue("owner", subject);
            return Results.Content((string)(await command.ExecuteScalarAsync(ct))!, "application/json");
        });
        group.MapPut("/records/{id:guid}", async (Guid id, ConsumptionDraft draft, HttpRequest request, CancellationToken ct) =>
        {
            if (owner(request) is not { } subject) return Results.Forbid();
            var photos = draft.PhotoIds ?? [];
            if (id == Guid.Empty || draft.BeverageId == Guid.Empty ||
                draft.ConsumedOn == default || draft.Rating is < 1 or > 5 ||
                draft.Note?.Length > 500 || draft.Place?.Length > 160 ||
                photos.Length > 6 || photos.Any(x => x == Guid.Empty) || photos.Distinct().Count() != photos.Length ||
                (draft.BeverageId is null && draft.Beverage is null) ||
                (draft.Beverage is { } details && !Valid(details)))
                return Results.BadRequest(new { error = "请检查饮品、评分、日期或照片。" });

            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(ct);
            await using var transaction = await connection.BeginTransactionAsync(ct);
            async Task<object?> Execute(string statement, params (string, object)[] parameters)
            {
                await using var command = new NpgsqlCommand(statement, connection, transaction);
                command.Parameters.AddWithValue("owner", subject);
                foreach (var (key, value) in parameters) command.Parameters.AddWithValue(key, value);
                return await command.ExecuteScalarAsync(ct);
            }

            if (photos.Length > 0 && (long)(await Execute("""
                SELECT count(*) FROM kitchen_personal_media WHERE owner_id=@owner AND id=ANY(@photos)
                """, ("photos", photos)))! != photos.Length)
                return Results.BadRequest(new { error = "存在无法访问的照片。" });

            var profileId = draft.BeverageId;
            if (profileId is null && draft.Beverage is { } beverage)
            {
                profileId = (Guid)(await Execute("""
                    INSERT INTO beverage_profiles(owner_id,id,identity_key,body)
                    VALUES(@owner,@profile,@identity,CAST(@body AS jsonb))
                    ON CONFLICT(owner_id,identity_key) DO UPDATE SET identity_key=EXCLUDED.identity_key
                    RETURNING id
                    """, ("profile", Guid.NewGuid()), ("identity", Identity(beverage)),
                    ("body", JsonSerializer.Serialize(beverage, Json))))!;
            }

            if (await Execute("SELECT id FROM beverage_profiles WHERE owner_id=@owner AND id=@profile",
                    ("profile", profileId!.Value)) is null) return Results.NotFound();

            if (draft.BeverageId.HasValue && draft.Beverage is { } edited)
            {
                try
                {
                    await Execute("""
                        UPDATE beverage_profiles SET body=CAST(@body AS jsonb),identity_key=@identity
                        WHERE owner_id=@owner AND id=@profile RETURNING id
                        """, ("body", JsonSerializer.Serialize(edited, Json)), ("identity", Identity(edited)),
                        ("profile", profileId.Value));
                }
                catch (PostgresException error) when (error.SqlState == PostgresErrorCodes.UniqueViolation)
                {
                    return Results.Conflict(new { error = "已有相同饮品，请关联已有档案。" });
                }
            }

            await Execute("""
                INSERT INTO beverage_consumptions(owner_id,id,beverage_id,consumed_on,body)
                VALUES(@owner,@id,@profile,@day,CAST(@body AS jsonb))
                ON CONFLICT(owner_id,id) DO UPDATE SET beverage_id=EXCLUDED.beverage_id,
                    consumed_on=EXCLUDED.consumed_on,body=EXCLUDED.body RETURNING id
                """, ("id", id), ("profile", profileId.Value), ("day", draft.ConsumedOn),
                ("body", JsonSerializer.Serialize(new { draft.ConsumedOn, draft.Rating, draft.Note, draft.Place, photoIds = photos }, Json)));
            await transaction.CommitAsync(ct);
            return Results.Ok(new { id, beverageId = profileId.Value });
        });
        group.MapPut("/{id:guid}/favorite", async (Guid id, FavoriteDraft draft, HttpRequest request, CancellationToken ct) =>
        {
            if (owner(request) is not { } subject) return Results.Forbid();
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(ct);
            await using var command = new NpgsqlCommand(
                "UPDATE beverage_profiles SET favorite=@favorite WHERE owner_id=@owner AND id=@id", connection);
            command.Parameters.AddWithValue("owner", subject);
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("favorite", draft.Favorite);
            return await command.ExecuteNonQueryAsync(ct) == 0 ? Results.NotFound() : Results.NoContent();
        });
        group.MapDelete("/records/{id:guid}", async (Guid id, HttpRequest request, CancellationToken ct) =>
        {
            if (owner(request) is not { } subject) return Results.Forbid();
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(ct);
            await using var command = new NpgsqlCommand("DELETE FROM beverage_consumptions WHERE owner_id=@owner AND id=@id", connection);
            command.Parameters.AddWithValue("owner", subject);
            command.Parameters.AddWithValue("id", id);
            return await command.ExecuteNonQueryAsync(ct) == 0 ? Results.NotFound() : Results.NoContent();
        });
    }

    internal static bool Valid(BeverageDraft draft) =>
        draft.Name?.Trim().Length is > 0 and <= 120 &&
        draft.Category is "alcoholic" or "nonalcoholic" or "unknown" &&
        new[] { draft.Brand, draft.Kind, draft.Origin, draft.Producer, draft.Size }.All(x => x is null || x.Length <= 120) &&
        draft.AlcoholPercent is null or (>= 0 and <= 100) && draft.Vintage is null or (>= 1000 and <= 9999);

    internal static string Identity(BeverageDraft draft) => JsonSerializer.Serialize(new[]
    {
        Normalize(draft.Name), Normalize(draft.Brand), Normalize(draft.Producer),
        draft.Vintage?.ToString(CultureInfo.InvariantCulture) ?? ""
    });

    private static string Normalize(string? value) =>
        string.Join(" ", (value ?? "").Normalize(NormalizationForm.FormKC)
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)).ToUpperInvariant();
}
