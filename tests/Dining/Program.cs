using LinkoFamily;
using Microsoft.AspNetCore.RateLimiting;
using System.Net;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
var old = new DiningPlace("a", "Known restaurant", "Address", 31.2, 121.4, "food", "amap", 25, 4.2, 200);
var fresh = old with { Id = "b", Name = "New restaurant" };
var account = Guid.NewGuid().ToString();
Check(DiningAccount.Identity(account.ToUpperInvariant()) == DiningAccount.Identity(account.ToLowerInvariant()), "GUID account variants share same archive identity");
Check(DiningAccount.Identity("User-A") != DiningAccount.Identity("user-a"), "non-GUID subjects preserve case");
var archive = new DiningArchive();
archive.Choose(old, "automatic");
Check(DiningRecommendation.Weight(old, "familiar", archive) > DiningRecommendation.Weight(fresh, "familiar", archive), "regular places remain eligible and favored");
Check(DiningRecommendation.Weight(fresh, "fresh", archive) > DiningRecommendation.Weight(old, "fresh", archive), "fresh mode favors unseen choices");
Check(DiningRecommendation.Pick([old, fresh], "automatic", archive, "a", 0)?.Id == "b", "reroll skips only current choice");
Check(DiningRecommendation.Pick([old], "automatic", archive, "a", 0)?.Id == "a", "one restaurant is not excluded forever");
Check(DiningRecommendation.Pick([], "automatic", archive, null) is null, "empty search never fabricates a restaurant");
Check(DiningRecommendation.Pick([old with { Latitude = double.NaN }], "automatic", archive, null) is null, "invalid coordinates are rejected");
Check(DiningRecommendation.Weight(old, "budget", archive) > DiningRecommendation.Weight(old with { Cost = 200 }, "budget", archive), "real price affects budget mode");
Check(DiningRecommendation.Weight(old with { Cost = null, Rating = null }, "budget", archive) > 0, "missing metadata stays unknown and eligible");
var id = archive.History[0].Id;
archive.ConfirmEaten(Guid.Parse(id.ToString().ToUpperInvariant())); archive.ConfirmEaten(Guid.Parse(id.ToString().ToLowerInvariant()));
Check(archive.Habits[old.Id].Eaten == 1, "typed GUID and eaten confirmation are idempotent");
var snapshot = JsonSerializer.Serialize(archive); var restored = JsonSerializer.Deserialize<DiningArchive>(snapshot)!;
Check(restored.History[0].SelectedAt.Offset == TimeSpan.Zero && restored.History[0].EatenAt != null, "UTC timestamps persist");
using var data = JsonDocument.Parse("""{"status":"1","pois":[{"id":"A","name":"Real restaurant","location":"121.4,31.2","distance":"200","biz_ext":{"cost":[],"rating":"4.3"}},{"id":"A","name":"Duplicate","location":"121.4,31.2","distance":"100"},{"id":"bad","name":"Bad","location":"999,999","distance":"10"}]}""");
var parsed = DiningEndpoints.Parse(data.RootElement);
Check(parsed.Count == 1 && parsed[0].Cost == null && parsed[0].Rating == 4.3 && parsed[0].Longitude == 121.4, "provider parsing preserves absence, deduplicates and validates coordinates");

var builder = WebApplication.CreateBuilder(); builder.WebHost.UseUrls("http://127.0.0.1:0");
builder.Logging.ClearProviders();
builder.Services.AddAuthentication("test").AddScheme<AuthenticationSchemeOptions, TestIdentity>("test", _ => {}); builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options => options.AddFixedWindowLimiter("dining-search", limit => { limit.PermitLimit = 30; limit.Window = TimeSpan.FromMinutes(1); }));
builder.Services.AddSingleton<IHttpClientFactory, Provider>();
var app = builder.Build();app.UseAuthentication();app.UseAuthorization();app.UseRateLimiter();app.MapDiningEndpoints();await app.StartAsync();
try {
 using var client = new HttpClient { BaseAddress = new Uri(app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single()) };
 var body = new StringContent("""{"latitude":31.2,"longitude":121.4}""", System.Text.Encoding.UTF8, "application/json");
 Check((await client.PostAsync("/api/dining/nearby", body)).StatusCode == HttpStatusCode.Unauthorized, "user center auth required before provider access");
 client.DefaultRequestHeaders.Add("X-Test-User", "test");
 Check((await client.PostAsync("/api/dining/nearby", body)).StatusCode == HttpStatusCode.ServiceUnavailable, "missing key is explicit 503");
 builder.Configuration["Dining:AmapWebServiceKey"] = "test-key-not-a-credential";
 Check((await client.PostAsync("/api/dining/nearby", new StringContent("""{"latitude":91,"longitude":0}""", System.Text.Encoding.UTF8,"application/json"))).StatusCode == HttpStatusCode.BadRequest, "invalid location rejected");
 using var response = await client.PostAsync("/api/dining/nearby", body); var text = await response.Content.ReadAsStringAsync();
 Check(response.IsSuccessStatusCode && text.Contains("amap:A") && text.Contains("gcj02") && !text.Contains("test-key"), "real provider contract and coordinate system; key never returned");
 Provider.Fail = true;
 Check((await client.PostAsync("/api/dining/nearby", body)).StatusCode == HttpStatusCode.BadGateway, "provider failure is honest, never a fake fallback");
 Console.WriteLine("PASS: dining recommendation, persistence, provider and authenticated HTTP checks");
} finally { await app.StopAsync(); await app.DisposeAsync(); }
sealed class TestIdentity(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder) {
 protected override Task<AuthenticateResult> HandleAuthenticateAsync() => Task.FromResult(Request.Headers.ContainsKey("X-Test-User") ? AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier,"fixture-user")],"test")),"test")) : AuthenticateResult.NoResult());
}
sealed class Provider : IHttpClientFactory {
 public static bool Fail;
 public HttpClient CreateClient(string name) => new(new Handler());
 private sealed class Handler : HttpMessageHandler {
  protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
   if (Fail) throw new HttpRequestException("provider unavailable");
   if (request.RequestUri!.Host != "restapi.amap.com") throw new Exception("unexpected provider");
   var convert = request.RequestUri.AbsolutePath.Contains("convert");
   var result = convert ? """{"status":"1","locations":"121.405000,31.205000"}""" : """{"status":"1","pois":[{"id":"A","name":"Real restaurant","location":"121.4,31.2","distance":"200","biz_ext":{"cost":"25","rating":"4.3"}}]}""";
   if (!convert && Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(request.RequestUri.Query)["location"] != "121.405000,31.205000") throw new Exception("WGS84 must be converted before search");
   return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(result) });
  }
 }
}
