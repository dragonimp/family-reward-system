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
await app.StopAsync();

sealed class FixtureAuthentication(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory log, UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, log, encoder) {
    protected override Task<AuthenticateResult> HandleAuthenticateAsync() {
        var value = Request.Headers["X-Exercise-Test-Owner"].ToString();
        return Task.FromResult(Guid.TryParse(value, out _) ? AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub", value)], Scheme.Name)), Scheme.Name)) : AuthenticateResult.NoResult());
    }
}
