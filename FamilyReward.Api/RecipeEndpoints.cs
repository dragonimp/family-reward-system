using System.Text.Json;
using System.Security.Cryptography;
using Microsoft.Net.Http.Headers;
using Npgsql;

internal sealed record RecipeCategory(string Id, string Name, string Icon);
internal sealed record RecipeIngredient(string Name, decimal Quantity, string Unit);
internal sealed record RecipeStep(int Number, string Action, string[] Ingredients, string[] Utensils, string Instruction, string? IllustrationUrl);
internal sealed record KitchenRecipe(Guid RecipeId, string Name, string Category, string Description, int Servings,
    int Duration, string Difficulty, RecipeIngredient[] Ingredients, string[] Preparation, RecipeStep[] Steps,
    string[] Notes, string? CoverImage, string IllustrationStatus, int RecipeVersion, string Source, string[] MealPreferences);

internal static class RecipeEndpoints
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal static bool Valid(KitchenRecipe recipe) =>
        recipe.RecipeId != Guid.Empty && !string.IsNullOrWhiteSpace(recipe.Name) && !string.IsNullOrWhiteSpace(recipe.Category)
        && recipe.Servings > 0 && recipe.Duration > 0 && recipe.RecipeVersion > 0
        && recipe.Ingredients is { Length: > 0 } && recipe.Ingredients.All(i => !string.IsNullOrWhiteSpace(i.Name) && i.Quantity > 0 && !string.IsNullOrWhiteSpace(i.Unit))
        && recipe.Steps is { Length: > 0 } && recipe.Steps.Select(s => s.Number).SequenceEqual(Enumerable.Range(1, recipe.Steps.Length))
        && recipe.Steps.All(s => !string.IsNullOrWhiteSpace(s.Action) && !string.IsNullOrWhiteSpace(s.Instruction)
            && s.Ingredients is { Length: > 0 } && s.Utensils is { Length: > 0 })
        && recipe.Notes is { Length: > 0 } && !string.IsNullOrWhiteSpace(recipe.Source)
        && FoodSafetyValidated(recipe);

    private static bool FoodSafetyValidated(KitchenRecipe recipe)
    {
        var instructions = string.Join(" ", recipe.Steps.Select(s => s.Instruction).Concat(recipe.Notes));
        if (recipe.Ingredients.Any(i => i.Name.Contains("鸡蛋")) && !instructions.Contains("71°C")) return false;
        if (recipe.Ingredients.Any(i => i.Name.Contains("鸡肉") || i.Name.Contains("鸡胸") || i.Name.Contains("鸡腿"))
            && !instructions.Contains("74°C")) return false;
        return instructions.Contains("生熟") && instructions.Contains("洗手");
    }

    public static void MapRecipeEndpoints(this WebApplication app, string connectionString)
    {
        // These are original, public recipe assets, not user uploads. Native image
        // loaders do not attach the app's Bearer token. Typed route values constrain
        // the path; recipe versions are immutable and new drawings use a new version.
        app.MapGet("/api/recipe-illustrations/{id:guid}/v{version:int}/steps/{number:int}.jpg",
            IResult (Guid id, int version, int number, HttpResponse response) =>
            {
                if (version < 1 || number is < 1 or > 64) return Results.NotFound();
                var path = Path.Combine(AppContext.BaseDirectory, "recipe-illustrations", id.ToString("D"),
                    "v" + version, "step-" + number + ".jpg");
                if (!File.Exists(path)) return Results.NotFound();
                using var stream = File.OpenRead(path);
                var hash = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
                response.Headers.CacheControl = "public, max-age=31536000, immutable";
                return Results.File(path, "image/jpeg", entityTag: new EntityTagHeaderValue("\"" + hash + "\""));
            }).AllowAnonymous();
        var group = app.MapGroup("/api/recipes").RequireAuthorization();
        group.MapGet("/categories", async (HttpResponse response, CancellationToken ct) =>
        {
            response.Headers.CacheControl = "private, max-age=60";
            try
            {
                await using var connection = new NpgsqlConnection(connectionString);
                await connection.OpenAsync(ct);
                await using var command = new NpgsqlCommand("SELECT id,name,icon FROM kitchen_categories WHERE enabled ORDER BY position,id", connection);
                await using var reader = await command.ExecuteReaderAsync(ct);
                var categories = new List<RecipeCategory>();
                while (await reader.ReadAsync(ct)) categories.Add(new(reader.GetString(0), reader.GetString(1), reader.GetString(2)));
                return Results.Ok(new { categories, illustrationGenerationAvailable = false });
            }
            catch (PostgresException e) when (e.SqlState == "42P01") { return Unavailable(); }
        });
        group.MapGet("/random", async (string? category, Guid? exclude, string? meal, CancellationToken ct) =>
        {
            // Meal is a device-local preference. It never excludes the user's category.
            try
            {
                await using var connection = new NpgsqlConnection(connectionString);
                await connection.OpenAsync(ct);
                await using var command = new NpgsqlCommand("""
                    WITH candidates AS (
                      SELECT id, body FROM kitchen_recipes WHERE published AND (@category='' OR category_id=@category)
                    ), choices AS (
                      SELECT * FROM candidates WHERE id<>@exclude OR (SELECT count(*) FROM candidates)=1
                    )
                    SELECT body::text FROM choices
                    ORDER BY -ln(GREATEST(random(), 0.000001)) /
                      CASE WHEN body->'mealPreferences' ? @meal THEN 2.0 ELSE 1.0 END
                    LIMIT 1
                    """, connection);
                command.Parameters.AddWithValue("category", category == "all" ? "" : category ?? "");
                command.Parameters.AddWithValue("exclude", exclude ?? Guid.Empty);
                command.Parameters.AddWithValue("meal", meal ?? "");
                var body = await command.ExecuteScalarAsync(ct) as string;
                return body == null ? Results.NotFound(new { error = "这个分类暂时没有菜谱，请换个分类。" }) : Read(body);
            }
            catch (PostgresException e) when (e.SqlState == "42P01") { return Unavailable(); }
        });
        group.MapGet("/{id:guid}", async (Guid id, HttpResponse response, CancellationToken ct) =>
        {
            response.Headers.CacheControl = "private, no-cache";
            try
            {
                await using var connection = new NpgsqlConnection(connectionString);
                await connection.OpenAsync(ct);
                await using var command = new NpgsqlCommand("SELECT body::text FROM kitchen_recipes WHERE id=@id AND published", connection);
                command.Parameters.AddWithValue("id", id);
                var body = await command.ExecuteScalarAsync(ct) as string;
                return body == null ? Results.NotFound(new { error = "菜谱暂不可用。" }) : Read(body);
            }
            catch (PostgresException e) when (e.SqlState == "42P01") { return Unavailable(); }
        });
        group.MapPost("/{id:guid}/illustrations", (Guid id) => Results.Json(new
        {
            error = "步骤插画服务尚未接通，文字做法仍可阅读。",
            code = "recipe_illustrations_unavailable"
        }, statusCode: 503)).RequireRateLimiting("dining-search");
    }

    private static IResult Read(string body)
    {
        var recipe = JsonSerializer.Deserialize<KitchenRecipe>(body, Json);
        return recipe != null && Valid(recipe) ? Results.Ok(recipe) :
            Results.Json(new { error = "菜谱资料不完整，暂时无法展示。" }, statusCode: 503);
    }

    private static IResult Unavailable() => Results.Json(new { error = "菜谱服务正在准备，请稍后重试。" }, statusCode: 503);
}
