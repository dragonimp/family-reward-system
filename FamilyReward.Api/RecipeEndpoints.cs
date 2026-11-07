using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Globalization;
using Microsoft.Net.Http.Headers;
using Npgsql;

internal sealed record RecipeCategory(string Id, string Name, string Icon);
internal sealed record RecipeIngredient(string Name, decimal Quantity, string Unit);
internal sealed record RecipeStep(int Number, string Action, string[] Ingredients, string[] Utensils, string Instruction, string? IllustrationUrl);
internal sealed record KitchenRecipe(Guid RecipeId, string Name, string Category, string Description, int Servings,
    int Duration, string Difficulty, RecipeIngredient[] Ingredients, string[] Preparation, RecipeStep[] Steps,
    string[] Notes, string? CoverImage, string IllustrationStatus, int RecipeVersion, string Source, string[] MealPreferences)
{
    public string ShareUrl => $"{RecipeEndpoints.PublicOrigin}/api/recipes/{RecipeId:D}/share";
}

internal static class RecipeEndpoints
{
    internal const string PublicOrigin = "https://happylife.ai.impx.net";
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal static bool Valid(KitchenRecipe recipe) =>
        recipe.RecipeId != Guid.Empty && !string.IsNullOrWhiteSpace(recipe.Name) && !string.IsNullOrWhiteSpace(recipe.Category)
        && !string.IsNullOrWhiteSpace(recipe.Description) && !string.IsNullOrWhiteSpace(recipe.Difficulty)
        && recipe.Preparation is { Length: > 0 } && recipe.Preparation.All(p => !string.IsNullOrWhiteSpace(p))
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
        // Only curated, published recipes are public. Sharing never forwards user tokens.
        app.MapGet("/api/recipes/{id:guid}/share", async Task<IResult> (Guid id, HttpResponse response, CancellationToken ct) =>
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(ct);
            await using var command = new NpgsqlCommand("SELECT body::text FROM kitchen_recipes WHERE id=@id AND published", connection);
            command.Parameters.AddWithValue("id", id);
            var body = await command.ExecuteScalarAsync(ct) as string;
            if (body == null) return Results.Content("<!doctype html><meta charset=\"utf-8\"><title>菜谱暂不可用</title><p>菜谱暂不可用。</p>", "text/html; charset=utf-8", statusCode: 404);
            var recipe = JsonSerializer.Deserialize<KitchenRecipe>(body, Json);
            if (recipe == null || !Valid(recipe)) return Unavailable();
            response.Headers.CacheControl = "public, max-age=60";
            response.Headers["Content-Security-Policy"] = $"default-src 'none'; img-src {PublicOrigin}; style-src 'unsafe-inline'; base-uri 'none'";
            response.Headers["X-Content-Type-Options"] = "nosniff";
            response.Headers["Referrer-Policy"] = "no-referrer";
            return Results.Content(ShareHtml(recipe), "text/html; charset=utf-8");
        }).AllowAnonymous();
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

    internal static string ShareHtml(KitchenRecipe recipe)
    {
        static string E(string value) => HtmlEncoder.Default.Encode(value);
        static string? Picture(string? value) => Uri.TryCreate(value, UriKind.Absolute, out var url)
            && url.Scheme == "https" && url.Host == "happylife.ai.impx.net" && url.Port == 443 && url.UserInfo.Length == 0
            && url.AbsolutePath.StartsWith("/api/recipe-illustrations/", StringComparison.Ordinal) ? url.AbsoluteUri : null;
        var preview = Picture(recipe.CoverImage) ?? Picture(recipe.Steps.LastOrDefault()?.IllustrationUrl);
        var html = new StringBuilder($$"""
            <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <title>{{E(recipe.Name)}} · Linko Moment</title><meta name="description" content="{{E(recipe.Description)}}">
            <meta property="og:type" content="article"><meta property="og:title" content="{{E(recipe.Name)}}">
            <meta property="og:description" content="{{E(recipe.Description)}}"><meta property="og:url" content="{{E(recipe.ShareUrl)}}">
            <link rel="canonical" href="{{E(recipe.ShareUrl)}}">
            <style>body{margin:0;background:#f2f2f7;color:#172126;font:17px/1.7 -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:720px;margin:20px auto;padding:24px;background:white;border-radius:20px}h1{font-size:30px;line-height:1.3}h2{font-size:22px;margin-top:28px}h3{font-size:18px}img{display:block;width:100%;height:auto;border-radius:14px;margin:12px 0}li{margin:8px 0}p{white-space:pre-wrap}.meta,footer{color:#787883;font-size:14px}section{margin:24px 0}footer{margin-top:32px}</style>
            """);
        if (preview != null) html.Append($"<meta property=\"og:image\" content=\"{E(preview)}\">");
        html.Append($"</head><body><main><h1>{E(recipe.Name)}</h1><p class=\"meta\">{recipe.Duration} 分钟 · {E(recipe.Difficulty)} · {recipe.Servings} 人份</p><p>{E(recipe.Description)}</p><h2>食材</h2><ul>");
        foreach (var ingredient in recipe.Ingredients)
            html.Append($"<li>{E(ingredient.Name)} · {ingredient.Quantity.ToString("0.##", CultureInfo.InvariantCulture)} {E(ingredient.Unit)}</li>");
        html.Append("</ul><h2>准备工作</h2><ul>");
        foreach (var item in recipe.Preparation) html.Append($"<li>{E(item)}</li>");
        html.Append("</ul><h2>制作步骤</h2>");
        foreach (var step in recipe.Steps)
        {
            html.Append($"<section><h3>{step.Number}. {E(step.Action)}</h3>");
            if (Picture(step.IllustrationUrl) is { } image) html.Append($"<img src=\"{E(image)}\" alt=\"{E(step.Action)}\" loading=\"lazy\" decoding=\"async\">");
            html.Append($"<p>{E(step.Instruction)}</p></section>");
        }
        html.Append("<h2>注意事项</h2><ul>");
        foreach (var note in recipe.Notes) html.Append($"<li>{E(note)}</li>");
        return html.Append("</ul><footer>Linko Moment · 下厨房</footer></main></body></html>").ToString();
    }

    private static IResult Read(string body)
    {
        var recipe = JsonSerializer.Deserialize<KitchenRecipe>(body, Json);
        return recipe != null && Valid(recipe) ? Results.Ok(recipe) :
            Results.Json(new { error = "菜谱资料不完整，暂时无法展示。" }, statusCode: 503);
    }

    private static IResult Unavailable() => Results.Json(new { error = "菜谱服务正在准备，请稍后重试。" }, statusCode: 503);
}
