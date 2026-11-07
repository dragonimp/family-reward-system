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
        count++;
    }
    Check(count == 9, "initial original catalog count");
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
    client.DefaultRequestHeaders.Add("X-Test-User", "test");
    using var categories = JsonDocument.Parse(await client.GetStringAsync("/api/recipes/categories"));
    Check(categories.RootElement.GetProperty("categories").GetArrayLength() == 4, "categories come from database");
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
