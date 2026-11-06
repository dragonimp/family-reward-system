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
archive.History.Add(new() { Place = old });
archive.Habit(old.Id).Selected = 1;
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
var manualId = Guid.NewGuid();
archive.CheckIn(fresh, null, manualId, "  川菜  ");
archive.CheckIn(fresh, null, Guid.Parse(manualId.ToString().ToUpperInvariant()));
Check(archive.Habit(fresh.Id).CheckIns == 1 && archive.History[0].RestaurantType == "川菜", "manual retry does not double count");
var autoId = Guid.NewGuid();
var localTime = new DateTimeOffset(2026, 11, 6, 20, 0, 0, TimeSpan.FromHours(8));
archive.CheckIn(fresh, "familiar", autoId, at: localTime);
archive.CheckIn(fresh, "familiar", autoId);
archive.ConfirmEaten(autoId);
Check(archive.Habit(fresh.Id).CheckIns == 2 && archive.Habit(fresh.Id).Visits == 2 && archive.Habit(fresh.Id).Eaten == 0, "manual and automatic visits share a counter and do not require a second confirmation");
var checkInCopy = JsonSerializer.Deserialize<DiningArchive>(JsonSerializer.Serialize(archive))!;
Check(checkInCopy.History[0].SelectedAt.EqualsExact(localTime.ToUniversalTime()) && checkInCopy.History[1].CheckedIn && checkInCopy.Habit(fresh.Id).CheckIns == 2, "check-in count and UTC time persist");
var legacy = JsonSerializer.Deserialize<DiningArchive>("""{"Habits":{"a":{"Selected":1,"Eaten":1,"Skipped":0}}}""")!;
Check(legacy.Habit("a").Visits == 1 && legacy.Habit("a").CheckIns == 0, "old preference records are retained and not counted as check-ins");
foreach (var mood in new[] { "automatic", "familiar" })
    Check(DiningRecommendation.Weight(fresh, mood, archive) > DiningRecommendation.Weight(fresh with { Id = "c" }, mood, archive), "check-ins improve recommendation weight");
Check(DiningMeal.Current(localTime.AddHours(-15)) == DiningMealPeriod.Breakfast && DiningMeal.Current(localTime.AddHours(-10).AddMinutes(30)) == DiningMealPeriod.Lunch, "meal transitions use local time");
Check(DiningMeal.Current(localTime.AddHours(-6)) == DiningMealPeriod.AfternoonTea && DiningMeal.Current(localTime.AddHours(-3).AddMinutes(-30)) == DiningMealPeriod.Dinner, "afternoon tea and dinner boundaries");
Check(DiningMeal.Current(localTime.AddHours(-11)) == DiningMealPeriod.Breakfast && DiningMeal.Current(localTime.AddHours(-11).ToOffset(TimeSpan.FromHours(-8))) == DiningMealPeriod.Dinner, "same instant in different time zones");
var breakfast = old with { Name = "阿婆早餐", Category = "中餐厅" };
var tea = fresh with { Name = "珍珠奶茶", Category = "餐饮服务;快餐厅" };
var steak = old with { Id = "c", Name = "Steak House", Category = "restaurant" };
DiningPlace[] options = [breakfast, tea, steak];
Check(options.Where(p => DiningMeal.Includes(DiningMealPeriod.Breakfast, p)).SequenceEqual([breakfast]), "breakfast filters tea and main meals");
Check(options.Where(p => DiningMeal.Includes(DiningMealPeriod.AfternoonTea, p)).SequenceEqual([tea]), "tea filters out main meals");
foreach (var meal in new[] { DiningMealPeriod.Lunch, DiningMealPeriod.Dinner })
    Check(options.Where(p => DiningMeal.Includes(meal, p)).SequenceEqual([steak]), "lunch and dinner require main meals");
Check(DiningRecommendation.Pick(new[] { tea }.Where(p => DiningMeal.Includes(DiningMealPeriod.Lunch, p)), "familiar", archive, null) is null, "familiarity cannot bypass the mealtime filter");
Check(DiningTrip.Walk5.Includes(300) && !DiningTrip.Walk5.Includes(300.1), "walking 5 minutes uses raw inclusive seconds");
Check(DiningTrip.Walk10.Includes(600) && DiningTrip.Drive10.Includes(600) && !DiningTrip.Drive10.Includes(601), "10 minute limits are inclusive");
Check(DiningTrip.Drive20.Driving() && !DiningTrip.Walk10.Driving() && DiningTrip.Drive20.Includes(1200) && !DiningTrip.Drive20.Includes(1201), "driving 20 minutes uses the selected transport and limit");
Check(!DiningTrip.Walk5.Includes(null) && !DiningTrip.Drive20.Includes(double.NaN) && DiningTrip.Unrestricted.Includes(null), "unknown route times never pass an active filter");
var manualArchive = new DiningArchive();
Check(manualArchive.ManualRestaurant(" ", 31, 121) is null && manualArchive.ManualRestaurant("新店", double.NaN, 121) is null, "manual entry requires name and valid coordinates");
var manualPlace = manualArchive.ManualRestaurant("  新店  ", 31, 121, "  上海市黄浦区  ")!;
Check(manualPlace.Address == "上海市黄浦区", "manual check-in keeps display address and location");
manualArchive.CheckIn(manualPlace, null, manualId, "川菜");
manualArchive.CheckIn(manualPlace, null, manualId);
var relocated = manualArchive.ManualRestaurant("新店", 31.0002, 121)!;
Check(relocated.Id == manualPlace.Id && relocated.Latitude == 31.0002, "repeat manual visits keep identity and record fresh coordinates");
manualArchive.CheckIn(relocated, null, autoId);
Check(manualArchive.Habit(manualPlace.Id).CheckIns == 2 && manualArchive.History.Count == 2, "manual check-ins use the shared ledger");
Check(manualArchive.ManualRestaurant("新店", 31.002, 121)?.Id != manualPlace.Id, "different locations are kept separate");
manualArchive.History.Clear();
var decodedManual = JsonSerializer.Deserialize<DiningArchive>(JsonSerializer.Serialize(manualArchive))!;
Check(decodedManual.ManualRestaurant("新店", 31, 121)?.Id == manualPlace.Id, "manual identity survives storage and history pruning");
var nearNoodles = old with { Name = "老街面馆", DistanceMeters = 2000 };
var farNoodles = nearNoodles with { Id = "far", DistanceMeters = 2000.1 };
DiningPlace[] optionsAtTea = [tea, nearNoodles, farNoodles];
IEnumerable<DiningPlace> FilterAtTea(DiningFood food) => optionsAtTea.Where(p => food.Includes(p, DiningMealPeriod.AfternoonTea) && DiningTrip.Nearby2km.IncludesDistance(p.DistanceMeters));
Check(FilterAtTea(DiningFood.Noodles).SequenceEqual([nearNoodles]), "explicit noodles override afternoon tea while keeping the 2 km limit");
Check(FilterAtTea(DiningFood.Smart).SequenceEqual([tea]), "restoring smart returns afternoon tea with the same distance");
Check(!DiningTrip.Nearby2km.HasTimeLimit() && !DiningTrip.Nearby2km.IncludesDistance(double.NaN), "distance range does not require a route ETA");
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
 var routeBody = new StringContent("""{"mode":"walking","origin":{"latitude":31.205,"longitude":121.405},"destinations":[{"latitude":31.2,"longitude":121.4},{"latitude":31.2,"longitude":121.41}]}""", System.Text.Encoding.UTF8, "application/json");
 Check((await client.PostAsync("/api/dining/route-times", routeBody)).StatusCode == HttpStatusCode.Unauthorized, "route times require authentication");
 client.DefaultRequestHeaders.Add("X-Test-User", "test");
 Check((await client.PostAsync("/api/dining/nearby", body)).StatusCode == HttpStatusCode.ServiceUnavailable, "missing key is explicit 503");
 builder.Configuration["Dining:AmapWebServiceKey"] = "test-key-not-a-credential";
 Check((await client.PostAsync("/api/dining/nearby", new StringContent("""{"latitude":91,"longitude":0}""", System.Text.Encoding.UTF8,"application/json"))).StatusCode == HttpStatusCode.BadRequest, "invalid location rejected");
 using var response = await client.PostAsync("/api/dining/nearby", body); var text = await response.Content.ReadAsStringAsync();
 Check(response.IsSuccessStatusCode && text.Contains("amap:A") && text.Contains("gcj02") && !text.Contains("test-key"), "real provider contract and coordinate system; key never returned");
 using var payload = JsonDocument.Parse(text);
 var center = payload.RootElement.GetProperty("searchCenter");
 Check(center.GetProperty("latitude").GetDouble() == 31.205 && center.GetProperty("longitude").GetDouble() == 121.405, "cross-provider matching receives the converted search center");
 Check(payload.RootElement.GetProperty("restaurants")[0].GetProperty("cost").GetDouble() == 25, "real per-person price retained");
 using var routeResponse = await client.PostAsync("/api/dining/route-times", routeBody);
 using var routePayload = JsonDocument.Parse(await routeResponse.Content.ReadAsStringAsync());
 var times = routePayload.RootElement.GetProperty("seconds");
 Check(routeResponse.IsSuccessStatusCode && times[0].GetDouble() == 300 && times[1].ValueKind == JsonValueKind.Null, "route durations preserve destination order and unknown routes");
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
   if (request.RequestUri.AbsolutePath.StartsWith("/v5/direction/", StringComparison.Ordinal)) {
    var query = Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(request.RequestUri.Query);
    if (request.RequestUri.AbsolutePath != "/v5/direction/walking" || query["origin"] != "121.405000,31.205000" || query["show_fields"] != "cost")
        throw new Exception("route lookup must send GCJ-02 origin and request walking cost");
    var content = query["destination"] == "121.400000,31.200000"
        ? """{"status":"1","route":{"paths":[{"cost":{"duration":"300"}}]}}"""
        : """{"status":"1","route":{"paths":[{"distance":"400"}]}}""";
    return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(content) });
   }
   var convert = request.RequestUri.AbsolutePath.Contains("convert");
   var result = convert ? """{"status":"1","locations":"121.405000,31.205000"}""" : """{"status":"1","pois":[{"id":"A","name":"Real restaurant","location":"121.4,31.2","distance":"200","biz_ext":{"cost":"25","rating":"4.3"}}]}""";
   if (!convert && Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(request.RequestUri.Query)["location"] != "121.405000,31.205000") throw new Exception("WGS84 must be converted before search");
   return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(result) });
  }
 }
}
