using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Options;

if (LinkoFamily.ExerciseSummaryText.Format("慢跑",20,1800,null,[-3.5]) != "慢跑 · 00:00:20\n1.80 公里\n海拔 -3.5–-3.5 米") throw new Exception("Cross-platform activity summary changed");
var root = Path.Combine(Environment.GetEnvironmentVariable("ATLAS_BUILD_WORK") ?? throw new Exception("Managed build workspace required"), "exercise-contract-data");
var builder = WebApplication.CreateBuilder();
builder.Logging.ClearProviders();
builder.Configuration["Exercise:DataDirectory"] = root;
builder.Services.AddAuthentication("fixture").AddScheme<AuthenticationSchemeOptions, FixtureAuthentication>("fixture", _ => { });
builder.Services.AddAuthorization();
await using var app = builder.Build();
app.Urls.Add("http://127.0.0.1:0");app.UseAuthentication();app.UseAuthorization();app.MapExerciseEndpoints();
await app.StartAsync();
var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
using var client = new HttpClient { BaseAddress = new Uri(address) };
var owner = Guid.NewGuid();client.DefaultRequestHeaders.Add("X-Exercise-Test-Owner", owner.ToString("D").ToUpperInvariant());
var id = Guid.NewGuid();var now = DateTimeOffset.UtcNow.AddMinutes(-5);var segment = Guid.NewGuid();
var record = new ExerciseEndpoints.Record(id, "徒步", now, now.AddMinutes(1), [new(now, now.AddMinutes(1), 80, 60)], true, [new(24, 118, now.AddSeconds(5), segment, -3.5, 8)]);
async Task Expect(HttpResponseMessage result, HttpStatusCode status) { if(result.StatusCode != status) throw new Exception($"Expected {status}, got {result.StatusCode}: {await result.Content.ReadAsStringAsync()}"); }
await Expect(await client.PutAsJsonAsync($"/api/exercise/records/{id:D}".ToUpperInvariant().Replace("/API/EXERCISE/RECORDS/","/api/exercise/records/"), record), HttpStatusCode.OK);
client.DefaultRequestHeaders.Remove("X-Exercise-Test-Owner");client.DefaultRequestHeaders.Add("X-Exercise-Test-Owner", owner.ToString("D").ToLowerInvariant());
var read = await client.GetFromJsonAsync<ExerciseEndpoints.Record>($"/api/exercise/records/{id:D}");
if(read?.Route?[0].AltitudeMeters != -3.5 || read.Route[0].VerticalAccuracyMeters != 8) throw new Exception("Altitude not preserved");
await Expect(await client.PutAsJsonAsync($"/api/exercise/records/{id:D}", record), HttpStatusCode.OK);
var edit = new ExerciseEndpoints.Metadata("飞行", new ExerciseEndpoints.Activity(Guid.NewGuid(), Guid.NewGuid(), "Target"), "飞行");
await Expect(await client.PatchAsJsonAsync($"/api/exercise/records/{id:D}/metadata", edit), HttpStatusCode.OK);
var edited = await client.GetFromJsonAsync<ExerciseEndpoints.Record>($"/api/exercise/records/{id:D}");
if (edited?.Kind != "飞行" || edited.Activity != edit.Activity || edited.MetadataRevision == null ||
    edited.Route?.Single() != record.Route?.Single() || edited.Intervals.Single() != record.Intervals.Single())
    throw new Exception("Metadata updates must preserve measurements");
var listing = await client.GetFromJsonAsync<JsonElement>("/api/exercise/records");
if (!listing.GetProperty("records").EnumerateArray().Any(x => x.GetProperty("metadataRevision").GetGuid() == edited.MetadataRevision))
    throw new Exception("Metadata edit must be discoverable by other devices");
Console.WriteLine("PASS: workout edits and cross-device metadata revision preserve route and measurements");
var shared = record with { Id = Guid.NewGuid(), ActivityText = "徒步 · 00:01:00\n0.06 公里" };
await Expect(await client.PutAsJsonAsync($"/api/exercise/records/{shared.Id:D}", shared), HttpStatusCode.OK);
var sharedRead = await client.GetFromJsonAsync<ExerciseEndpoints.Record>($"/api/exercise/records/{shared.Id:D}");
if(sharedRead?.ActivityText != shared.ActivityText) throw new Exception("Shared activity text not preserved");
var modified = record with { Route = [new(24,118,now.AddSeconds(5),segment, 10,8)] };
await Expect(await client.PutAsJsonAsync($"/api/exercise/records/{id:D}", modified), HttpStatusCode.Conflict);
var invalid = record with { Id = Guid.NewGuid(), Route = [new(24,118,now.AddSeconds(5),segment, 10,-1)] };
await Expect(await client.PutAsJsonAsync($"/api/exercise/records/{invalid.Id:D}", invalid), HttpStatusCode.BadRequest);
var legacy = record with { Id = Guid.NewGuid(), Route = [new(24,118,now.AddSeconds(5),segment)] };
await Expect(await client.PutAsJsonAsync($"/api/exercise/records/{legacy.Id:D}", legacy), HttpStatusCode.OK);
var legacyJson = await client.GetStringAsync($"/api/exercise/records/{legacy.Id:D}");
if(legacyJson.Contains("altitudeMeters")) throw new Exception("Legacy canonical payload changed");
await Expect(await client.PutAsJsonAsync($"/api/exercise/records/{legacy.Id:D}", legacy), HttpStatusCode.OK);
client.DefaultRequestHeaders.Remove("X-Exercise-Test-Owner");client.DefaultRequestHeaders.Add("X-Exercise-Test-Owner", Guid.NewGuid().ToString());
await Expect(await client.GetAsync($"/api/exercise/records/{id:D}"), HttpStatusCode.NotFound);
client.DefaultRequestHeaders.Remove("X-Exercise-Test-Owner");client.DefaultRequestHeaders.Add("X-Exercise-Test-Owner", owner.ToString());
await Expect(await client.DeleteAsync($"/api/exercise/records/{id.ToString("D").ToUpperInvariant()}"), HttpStatusCode.OK);
await Expect(await client.PutAsJsonAsync($"/api/exercise/records/{id:D}", record), HttpStatusCode.Conflict);
Console.WriteLine("PASS: altitude roundtrip, negative elevation, invalid accuracy rejection, legacy replay, immutable conflicts, GUID case variants, account isolation and deletion tombstones");
const string shares = "/api/exercise/shares";
using var created = await client.PostAsJsonAsync(shares, new { kind = "飞行", name = "Host", workoutId = id });
await Expect(created, HttpStatusCode.OK);
var code = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetGuid();
var sharePath = $"{shares}/{code:D}";
await Expect(await client.PutAsJsonAsync(sharePath + "/track", new { workoutId = id, points = record.Route }), HttpStatusCode.OK);
using var guest = new HttpClient { BaseAddress = new Uri(address) };
await Expect(await guest.GetAsync(sharePath), HttpStatusCode.Unauthorized);
guest.DefaultRequestHeaders.Add("X-Exercise-Test-Owner", Guid.NewGuid().ToString());
var view = await guest.GetFromJsonAsync<JsonElement>(sharePath);
if (view.GetProperty("tracks").GetArrayLength() != 1 || view.GetProperty("workoutId").ValueKind != JsonValueKind.Null)
    throw new Exception("Viewing must not join a workout");
await Expect(await guest.PutAsJsonAsync(sharePath + "/track", new { workoutId = id, points = record.Route }), HttpStatusCode.Forbidden);
var guestWorkout = Guid.NewGuid();
await Expect(await guest.PutAsJsonAsync(sharePath + "/member", new { name = "Guest", workoutId = guestWorkout }), HttpStatusCode.OK);
await Expect(await guest.PutAsJsonAsync(sharePath + "/track", new { workoutId = id, points = record.Route }), HttpStatusCode.Forbidden);
await Expect(await guest.PutAsJsonAsync(sharePath + "/track", new { workoutId = guestWorkout, points = record.Route }), HttpStatusCode.OK);
view = await client.GetFromJsonAsync<JsonElement>(sharePath);
if (view.GetProperty("tracks").GetArrayLength() != 2 || view.GetProperty("tracks").EnumerateArray().Any(track => track.GetProperty("points").GetArrayLength() != 1))
    throw new Exception("Both participant tracks must be present");
await Expect(await guest.DeleteAsync(sharePath), HttpStatusCode.Forbidden);
await Expect(await guest.DeleteAsync(sharePath + "/member"), HttpStatusCode.OK);
await Expect(await guest.PutAsJsonAsync(sharePath + "/track", new { workoutId = guestWorkout, points = record.Route }), HttpStatusCode.Forbidden);
await Expect(await client.DeleteAsync(sharePath), HttpStatusCode.NoContent);
await Expect(await guest.GetAsync(sharePath), HttpStatusCode.NotFound);
Console.WriteLine("PASS: workout share authentication, viewing, membership, isolated tracks and revocation");
await app.StopAsync();

sealed class FixtureAuthentication(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory log, UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, log, encoder) {
    protected override Task<AuthenticateResult> HandleAuthenticateAsync() {
        var value = Request.Headers["X-Exercise-Test-Owner"].ToString();
        return Task.FromResult(Guid.TryParse(value, out _) ? AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub", value)], Scheme.Name)), Scheme.Name)) : AuthenticateResult.NoResult());
    }
}
