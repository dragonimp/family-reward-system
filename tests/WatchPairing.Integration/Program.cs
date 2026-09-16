extern alias familyapi;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

// Only a disposable, explicitly selected local database is accepted.
var database = Environment.GetEnvironmentVariable("PGDATABASE") ?? "";
if (!database.StartsWith("family_watch_pairing_test_")) throw new Exception("Select a disposable pairing test database");
Environment.SetEnvironmentVariable("PGHOST", "localhost");
Environment.SetEnvironmentVariable("ConnectionStrings__Default", new Npgsql.NpgsqlConnectionStringBuilder {
    Host = "localhost", Database = database, Username = Environment.UserName
}.ConnectionString);
Environment.SetEnvironmentVariable("FAMILY_REWARD_API_URLS", "http://127.0.0.1:5118");
using var factory = new PairingFactory();
using var parent = factory.CreateClient();
parent.DefaultRequestHeaders.Add("X-Test-Identity", "pairing-owner");
using var anonymous = factory.CreateClient();
using var other = factory.CreateClient();
other.DefaultRequestHeaders.Add("X-Test-Identity", "pairing-other");
static void Check(bool value, string message) { if (!value) throw new Exception(message); }
static async Task<JsonNode> Json(HttpResponseMessage response) {
    var body = await response.Content.ReadAsStringAsync();
    if (!response.IsSuccessStatusCode) throw new Exception($"Unexpected {response.StatusCode}: {body}");
    return JsonNode.Parse(body)!;
}
foreach (var client in new[] { parent, other }) await Json(await client.PostAsJsonAsync("/api/user/profile", new { channel = "pc", role = "parent" }));
var profile = await Json(await parent.GetAsync("/api/user/profile"));
var groups = await Json(await parent.GetAsync("/api/family-groups"));
var child = await Json(await parent.PostAsJsonAsync("/api/children", new { name = "Pairing integration " + Guid.NewGuid().ToString("N")[..8], familyGroupId = groups[0]!["id"]!.GetValue<int>() }));
var id = child["id"]!.GetValue<int>();
var challenge = await Json(await anonymous.PostAsJsonAsync("/api/watch/pairing", new { deviceName = "Integration Watch", platform = "watchos" }));
var code = challenge["code"]!.GetValue<string>();
var token = challenge["deviceToken"]!.GetValue<string>();
Check(!challenge["verificationUrl"]!.GetValue<string>().Contains(token), "QR leaked token");
using var watch = factory.CreateClient();
watch.DefaultRequestHeaders.Add("X-Watch-Device-Token", token);
Check((await Json(await watch.GetAsync("/api/watch/pairing")))["status"]!.GetValue<string>() == "pending", "pending");
Check((await watch.GetAsync("/api/watch/score")).StatusCode == HttpStatusCode.Unauthorized, "unapproved read");
var path = $"/api/children/{id}/pair-device";
Check((await anonymous.PostAsJsonAsync(path, new { code })).StatusCode == HttpStatusCode.Unauthorized, "anonymous approval");
anonymous.DefaultRequestHeaders.Add("X-App-User-Id", profile["appUserId"]!.GetValue<string>());
anonymous.DefaultRequestHeaders.Add("X-App-User-Role", "parent");
anonymous.DefaultRequestHeaders.Add("X-User-Id", "pairing-owner");
Check((await anonymous.PostAsJsonAsync(path, new { code })).StatusCode == HttpStatusCode.Unauthorized, "spoofed identity headers");
Check((await other.PostAsJsonAsync(path, new { code })).StatusCode == HttpStatusCode.Forbidden, "foreign child");
other.DefaultRequestHeaders.Add("X-App-User-Id", profile["appUserId"]!.GetValue<string>());
other.DefaultRequestHeaders.Add("X-App-User-Role", "parent");
Check((await other.PostAsJsonAsync(path, new { code })).StatusCode == HttpStatusCode.Forbidden, "authenticated spoofed app profile");
var responses = await Task.WhenAll(parent.PostAsJsonAsync(path, new { code }), parent.PostAsJsonAsync(path, new { code }));
var first = await Json(responses[0]); var second = await Json(responses[1]);
Check(first["deviceId"]!.GetValue<int>() == second["deviceId"]!.GetValue<int>(), "duplicate write");
Check((await Json(await watch.GetAsync("/api/watch/pairing")))["status"]!.GetValue<string>() == "approved", "approval poll");
Check((await Json(await watch.GetAsync("/api/watch/score")))["children"]![0]!["id"]!.GetValue<int>() == id, "bound wrong child");
// A new process/session store must still recognize an already approved token.
using (var restartedFactory = new PairingFactory()) {
    using var recoveredWatch = restartedFactory.CreateClient();
    recoveredWatch.DefaultRequestHeaders.Add("X-Watch-Device-Token", token);
    Check((await Json(await recoveredWatch.GetAsync("/api/watch/pairing")))["status"]!.GetValue<string>() == "approved", "durable approval recovery");
}
var next = await Json(await anonymous.PostAsJsonAsync("/api/watch/pairing", new { deviceName = "Second watch" }));
Check((await parent.PostAsJsonAsync(path, new { code = next["code"]!.GetValue<string>() })).StatusCode == HttpStatusCode.Conflict, "second device accepted");
await Json(await parent.DeleteAsync($"/api/children/{id}/devices/{first["deviceId"]!.GetValue<int>()}"));
Check((await Json(await watch.GetAsync("/api/watch/pairing")))["status"]!.GetValue<string>() == "expired", "revoked recovery");
Console.WriteLine("PASS: HTTP flow, authenticated parent, spoofed headers rejected, foreign child rejected, concurrent confirmation, actual child score, one-device limit, revocation");

sealed class PairingFactory : WebApplicationFactory<familyapi::Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder) {
        builder.UseContentRoot(Path.GetFullPath("FamilyReward.Api"));
        builder.ConfigureTestServices(services => {
            services.AddAuthentication(options => { options.DefaultAuthenticateScheme = "Fixture"; options.DefaultChallengeScheme = "Fixture"; })
                .AddScheme<AuthenticationSchemeOptions, FixtureAuthentication>("Fixture", _ => { });
        });
    }
}
sealed class FixtureAuthentication(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync() {
        var name = Request.Headers["X-Test-Identity"].ToString();
        if (name.Length == 0) return Task.FromResult(AuthenticateResult.NoResult());
        var principal = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, name), new Claim("preferred_username", name) }, "Fixture"));
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, "Fixture")));
    }
}
