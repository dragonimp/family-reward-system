using System.Text.Json.Nodes;
using Npgsql;

internal static class ModulePreferenceEndpoints
{
    internal static readonly string[] Keys = ["dining", "growth", "activities", "exercise"];
    internal static JsonObject Defaults() => new() { ["dining"] = true, ["growth"] = true, ["activities"] = true, ["exercise"] = true };
    static bool Boolean(JsonNode? value, out bool flag) { flag = false; return value is JsonValue v && v.TryGetValue(out flag); }
    static async Task<JsonObject> Read(NpgsqlConnection c, string owner)
    {
        await using var q = new NpgsqlCommand("SELECT jsonb_build_object('sections',sections,'version',version,'initialized',true,'updatedAt',updated_at)::text FROM account_module_preferences WHERE owner_id=@owner", c);
        q.Parameters.AddWithValue("owner", owner);
        return await q.ExecuteScalarAsync() is string text ? JsonNode.Parse(text)!.AsObject() : new JsonObject { ["sections"] = Defaults(), ["version"] = 0, ["initialized"] = false };
    }
    public static void MapModulePreferences(this WebApplication app, string cs, Func<HttpRequest,string?> ownerFor)
    {
        var group = app.MapGroup("/api/user/module-preferences").RequireAuthorization();
        group.AddEndpointFilter(async (context, next) => {
            if (ownerFor(context.HttpContext.Request) is null) return Results.Unauthorized();
            context.HttpContext.Response.Headers.CacheControl = "private, no-store";
            return await next(context);
        });
        group.MapGet("", async (HttpRequest r) => { await using var c = new NpgsqlConnection(cs); await c.OpenAsync(); return Results.Json(await Read(c, ownerFor(r)!)); });
        group.MapPost("/bootstrap", async (JsonObject input, HttpRequest r) => {
            if (input["sections"] is not JsonObject legacy || legacy.Any(p => !Keys.Contains(p.Key) || !Boolean(p.Value, out _))) return Results.BadRequest(new { error = "栏目设置格式无效。" });
            var sections = Defaults(); foreach (var p in legacy) sections[p.Key] = p.Value!.DeepClone();
            await using var c = new NpgsqlConnection(cs); await c.OpenAsync();
            await using var q = new NpgsqlCommand("INSERT INTO account_module_preferences(owner_id,sections) VALUES(@owner,@sections::jsonb) ON CONFLICT(owner_id) DO NOTHING", c);
            q.Parameters.AddWithValue("owner", ownerFor(r)!); q.Parameters.AddWithValue("sections", sections.ToJsonString()); await q.ExecuteNonQueryAsync();
            // A second device's legacy defaults never overwrite the account's saved configuration.
            return Results.Json(await Read(c, ownerFor(r)!));
        });
        group.MapPatch("", async (JsonObject input, HttpRequest r) => {
            var key = input["key"]?.ToString();
            if (key is null || !Keys.Contains(key) || !Boolean(input["enabled"], out var enabled) || !long.TryParse(input["expectedVersion"]?.ToString(), out var version) || version < 1) return Results.BadRequest(new { error = "请重新读取栏目设置后再修改。" });
            await using var c = new NpgsqlConnection(cs); await c.OpenAsync();
            await using var q = new NpgsqlCommand("UPDATE account_module_preferences SET sections=jsonb_set(sections,ARRAY[@key],to_jsonb(@enabled::boolean)),version=version+1,updated_at=now() WHERE owner_id=@owner AND version=@version", c);
            q.Parameters.AddWithValue("key", key); q.Parameters.AddWithValue("enabled", enabled); q.Parameters.AddWithValue("owner", ownerFor(r)!); q.Parameters.AddWithValue("version", version);
            var count = await q.ExecuteNonQueryAsync(); var current = await Read(c, ownerFor(r)!);
            if (count == 0) { current["error"] = "设置已在其他设备更新，请核对后重试。"; return Results.Json(current, statusCode:409); }
            return Results.Json(current);
        });
    }
}
