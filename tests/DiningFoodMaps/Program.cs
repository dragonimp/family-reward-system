using System.Net;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Options;
using Npgsql;

var cs = Environment.GetEnvironmentVariable("DINING_TEST_POSTGRES") ?? throw new InvalidOperationException("Set DINING_TEST_POSTGRES to a disposable, empty test database.");
await using (var connection = new NpgsqlConnection(cs))
{
    await connection.OpenAsync();
    using var script = new StreamReader(typeof(TestIdentity).Assembly.GetManifestResourceStream("FoodMapsMigration.sql")!);
    using var extension = new StreamReader(typeof(TestIdentity).Assembly.GetManifestResourceStream("NativeMapMigration.sql")!);
    var migration = await script.ReadToEndAsync() + "\n" + await extension.ReadToEndAsync();
    await using var command = new NpgsqlCommand(migration, connection);
    await command.ExecuteNonQueryAsync();
}

var builder = WebApplication.CreateBuilder();
builder.WebHost.UseUrls("http://127.0.0.1:0");
builder.Logging.ClearProviders();
builder.Services.AddAuthentication("food-test").AddScheme<AuthenticationSchemeOptions, TestIdentity>("food-test", _ => {});
builder.Services.AddAuthorization();
await using var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();
app.MapDiningFoodMaps(cs, r => r.HttpContext.User.FindFirstValue(ClaimTypes.NameIdentifier));
await app.StartAsync();
using var client = new HttpClient
{
    BaseAddress = new Uri(app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single())
};
const string root = "/api/dining/food-maps/";
var id = Guid.NewGuid();
var place = Guid.NewGuid();
var center = new { id, name = "测试饭圈", latitude = 24.5, longitude = 118.1, coordinateSystem = "wgs84" };
var payload = new { id = place, name = "测试炒粉", category = "炒粉", latitude = 24.5001, longitude = 118.1001,
    coordinateSystem = "wgs84", locationText = "东门附近" };
var map = root + id;
var item = map + "/places/" + place;
using var denied = await client.GetAsync(root);
Check(denied.StatusCode == HttpStatusCode.Unauthorized, "anonymous request denied");

client.DefaultRequestHeaders.Add("X-Test-User", "owner");
Check((await client.PostAsJsonAsync(root, center)).IsSuccessStatusCode, "create circle");
Check((await client.PostAsJsonAsync(root, center with { id = Guid.NewGuid() })).StatusCode == HttpStatusCode.Conflict, "nearby duplicate");
Check((await client.PutAsJsonAsync(map + "/places", payload with { latitude = 25 })).StatusCode == HttpStatusCode.BadRequest, "outside radius rejected");
Check((await client.PutAsJsonAsync(map + "/places", payload)).IsSuccessStatusCode, "save place");
Check((await client.GetFromJsonAsync<JsonElement>(map)).GetProperty("places").GetArrayLength() == 0, "pending pins are hidden");
Check((await client.GetFromJsonAsync<JsonElement>(map + "/pending")).GetArrayLength() == 1, "owner can review pending pin");
Check((await client.PutAsync(item + "/visit", null)).StatusCode == HttpStatusCode.NotFound, "pending pin cannot be visited");
Check((await client.PutAsync(item + "/approve", null)).StatusCode == HttpStatusCode.NoContent, "owner approval publishes the pin");

await client.PutAsync(item + "/visit", null);
await client.PutAsync(item + "/visit", null);
await client.PutAsJsonAsync(item + "/review", new { stars = 3 });
await client.PutAsJsonAsync(item + "/review", new { stars = 5 });
var before = await client.GetFromJsonAsync<JsonElement>(map);
long version = before.GetProperty("dataVersion").GetInt64();
Check(before.GetProperty("places")[0].GetProperty("visits").GetInt32() == 1, "visit deduplicated");

client.DefaultRequestHeaders.Remove("X-Test-User");
client.DefaultRequestHeaders.Add("X-Test-User", "follower");
Check((await client.GetFromJsonAsync<JsonElement>(root)).GetArrayLength() == 1, "discover");
Check((await client.GetAsync(map)).StatusCode == HttpStatusCode.NotFound, "non-member snapshot denied");
Check((await client.PutAsync(map + "/follow", null)).IsSuccessStatusCode, "follow");
Check((await client.PutAsync(item + "/approve", null)).StatusCode == HttpStatusCode.NotFound, "followers cannot approve");
Check((await client.GetAsync(map + "/pending")).StatusCode == HttpStatusCode.NotFound, "followers cannot browse pending pins");
Check((await client.PutAsJsonAsync(map + "/places", payload)).StatusCode == HttpStatusCode.BadRequest, "another user cannot overwrite place");
await client.PutAsJsonAsync(item + "/review", new { stars = 2, note = "好找" });
var delta = await client.GetFromJsonAsync<JsonElement>($"{map}?since={version}");
var update = delta.GetProperty("places")[0];
Check(!delta.GetProperty("full").GetBoolean() && update.GetProperty("rating").GetDecimal() == 3.5m, "delta includes average with one score per user");
Check(!update.TryGetProperty("note", out _), "offline response omits comments");
Check((await client.GetFromJsonAsync<JsonElement>(item + "/reviews")).GetArrayLength() == 1, "online comments available");
await client.DeleteAsync(map + "/follow");
Check((await client.GetAsync(map)).StatusCode == HttpStatusCode.NotFound, "unfollow revokes online access");
Console.WriteLine("PASS: authenticated food-map discovery, duplicate detection, membership, visit deduplication, rating updates and deltas.");

static void Check(bool condition, string detail) { if (!condition) throw new Exception(detail); }

sealed class TestIdentity(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("X-Test-User", out var user)) return Task.FromResult(AuthenticateResult.NoResult());
        var identity = new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, user.ToString())], Scheme.Name);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name)));
    }
}
