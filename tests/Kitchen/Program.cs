using System.Net;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using Npgsql;

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
var connectionString = Environment.GetEnvironmentVariable("KITCHEN_TEST_DSN") ?? throw new Exception("Isolated DB required");
await using (var connection = new NpgsqlConnection(connectionString))
{
    await connection.OpenAsync();
    await using var command = new NpgsqlCommand("SELECT body::text FROM kitchen_recipes", connection);
    await using var reader = await command.ExecuteReaderAsync();
    var count = 0;
    while (await reader.ReadAsync())
    {
        var recipe = JsonSerializer.Deserialize<KitchenRecipe>(reader.GetString(0), RecipeEndpoints.Json)!;
        Check(RecipeEndpoints.Valid(recipe), "imported recipe must have complete ingredients, steps and notes");
        Check(!RecipeEndpoints.Valid(recipe with { Steps = [] }), "empty steps rejected");
        Check(recipe.Steps.SelectMany(s => s.Ingredients).All(i => !string.IsNullOrWhiteSpace(i)), "step ingredient references populated");
        Check(recipe.IllustrationStatus == "ready" && recipe.Steps.All(s => s.IllustrationUrl == $"https://happylife.ai.impx.net/api/recipe-illustrations/{recipe.RecipeId:D}/v{recipe.RecipeVersion}/steps/{s.Number}.jpg"), "migration attaches the exact recipe version and ordered step images");
        foreach (var step in recipe.Steps)
            Check(File.Exists(Path.Combine(AppContext.BaseDirectory, "recipe-illustrations", recipe.RecipeId.ToString("D"), "v" + recipe.RecipeVersion, "step-" + step.Number + ".jpg")), "all published step assets are packaged");
        count++;
    }
    Check(count == 30, "expanded original catalog count");
}
var builder = WebApplication.CreateBuilder();
builder.WebHost.UseUrls("http://127.0.0.1:0");
builder.Logging.ClearProviders();
builder.Services.AddAuthentication("test").AddScheme<AuthenticationSchemeOptions, TestIdentity>("test", _ => {});
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(o => o.AddFixedWindowLimiter("dining-search", v => { v.PermitLimit = 10; v.Window = TimeSpan.FromMinutes(1); }));
var app = builder.Build();
app.UseAuthentication(); app.UseAuthorization(); app.UseRateLimiter(); app.MapRecipeEndpoints(connectionString);
await app.StartAsync();
try
{
    using var client = new HttpClient { BaseAddress = new Uri(app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single()) };
    Check((await client.GetAsync("/api/recipes/categories")).StatusCode == HttpStatusCode.Unauthorized, "categories require app authentication");
    var drawing = "/api/recipe-illustrations/B3FCCE06-1D3C-5B2F-822B-0419BEAE6ED4/v1/steps/1.jpg";
    using var picture = await client.GetAsync(drawing);
    Check(picture.StatusCode == HttpStatusCode.OK && picture.Content.Headers.ContentType?.MediaType == "image/jpeg", "original recipe images support anonymous native loaders and GUID variants");
    Check((await picture.Content.ReadAsByteArrayAsync()).Take(2).SequenceEqual(new byte[] { 255, 216 }), "image response contains actual JPEG bytes");
    Check(picture.Headers.CacheControl?.Extensions.Any(v => v.Name == "immutable") == true && picture.Headers.ETag != null, "immutable version has cache headers");
    using var cachedRequest = new HttpRequestMessage(HttpMethod.Get, drawing);
    cachedRequest.Headers.IfNoneMatch.Add(picture.Headers.ETag!);
    Check((await client.SendAsync(cachedRequest)).StatusCode == HttpStatusCode.NotModified, "unchanged images do not download again");
    Check((await client.GetAsync("/api/recipe-illustrations/b3fcce06-1d3c-5b2f-822b-0419beae6ed4/v99/steps/1.jpg")).StatusCode == HttpStatusCode.NotFound, "missing image versions do not return a stale drawing");
    Check((await client.GetAsync("/api/recipe-illustrations/b3fcce06-1d3c-5b2f-822b-0419beae6ed4/v1/steps/-1.jpg")).StatusCode == HttpStatusCode.NotFound, "invalid step paths rejected");
    client.DefaultRequestHeaders.Add("X-Test-User", "test");
    using var categories = JsonDocument.Parse(await client.GetStringAsync("/api/recipes/categories"));
    Check(categories.RootElement.GetProperty("categories").GetArrayLength() == 4, "categories come from database");
    var categoryItems = categories.RootElement.GetProperty("categories").EnumerateArray().ToArray();
    Check(categoryItems.Any(c => c.GetProperty("id").GetString() == "dessert" && c.GetProperty("name").GetString() == "甜品")
        && categoryItems.All(c => c.GetProperty("id").GetString() != "all"), "dessert replaces the explicit anything category");
    foreach (var path in new[] { "/api/recipes/random", "/api/recipes/random?category=", "/api/recipes/random?category=all" })
    {
        var any = JsonSerializer.Deserialize<KitchenRecipe>(await client.GetStringAsync(path), RecipeEndpoints.Json)!;
        Check(RecipeEndpoints.Valid(any), "unselected and legacy-anything requests return a complete recipe");
    }
    var dessert = JsonSerializer.Deserialize<KitchenRecipe>(await client.GetStringAsync("/api/recipes/random?category=dessert&meal=lunch"), RecipeEndpoints.Json)!;
    Check(dessert.Category == "dessert", "explicit dessert choice survives lunch preference");
    var first = JsonSerializer.Deserialize<KitchenRecipe>(await client.GetStringAsync("/api/recipes/random?category=noodles&meal=afternoonTea"), RecipeEndpoints.Json)!;
    Check(first.Category == "noodles", "explicit category survives mealtime preference");
    var next = JsonSerializer.Deserialize<KitchenRecipe>(await client.GetStringAsync("/api/recipes/random?category=noodles&exclude=" + first.RecipeId), RecipeEndpoints.Json)!;
    Check(next.RecipeId != first.RecipeId, "reroll excludes previous recipe when alternatives exist");
    var uppercase = await client.GetStringAsync("/api/recipes/" + first.RecipeId.ToString().ToUpperInvariant());
    var lowercase = await client.GetStringAsync("/api/recipes/" + first.RecipeId.ToString().ToLowerInvariant());
    Check(uppercase == lowercase, "UUID casing resolves the same recipe through PostgreSQL");
    Check((await client.GetAsync("/api/recipes/random?category=missing")).StatusCode == HttpStatusCode.NotFound, "empty category has a useful error");
    Check((await client.PostAsync("/api/recipes/" + first.RecipeId + "/illustrations", null)).StatusCode == HttpStatusCode.ServiceUnavailable, "missing shared image capability never returns a fake queued task");
    Console.WriteLine("PASS: PostgreSQL recipe import, validation, category filtering, reroll, UUID and authenticated HTTP");
}
finally { await app.StopAsync(); await app.DisposeAsync(); }
sealed class TestIdentity(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync() => Task.FromResult(Request.Headers.ContainsKey("X-Test-User")
        ? AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "fixture-user")], "test")), "test"))
        : AuthenticateResult.NoResult());
}
