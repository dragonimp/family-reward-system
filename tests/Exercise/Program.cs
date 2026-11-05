using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;
using System.Text.Encodings.Web;
using System.Text.Json;

var folder = Path.Combine(Path.GetTempPath(), "exercise-sync-checks-" + Guid.NewGuid().ToString("N"));
var builder = WebApplication.CreateBuilder(); builder.WebHost.UseUrls("http://127.0.0.1:0");
builder.Configuration["Exercise:DataDirectory"] = folder;
builder.Services.AddAuthentication("Test").AddScheme<AuthenticationSchemeOptions, TestAuth>("Test", _ => {});
builder.Services.AddAuthorization();
var app=builder.Build();app.UseAuthentication();app.UseAuthorization();app.MapExerciseEndpoints();await app.StartAsync();
try {
 var address=app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
 using var owner=new HttpClient{BaseAddress=new Uri(address)};owner.DefaultRequestHeaders.Add("X-Test-User","owner");
 using var other=new HttpClient{BaseAddress=new Uri(address)};other.DefaultRequestHeaders.Add("X-Test-User","other");
 using var anonymous=new HttpClient{BaseAddress=new Uri(address)};
 var start=DateTimeOffset.UtcNow.AddHours(-1);var id=Guid.NewGuid();
 var record=new ExerciseEndpoints.Record(id,"散步",start,start.AddMinutes(30),[new(start,start.AddMinutes(10),100,80),new(start.AddMinutes(20),start.AddMinutes(30),100,80)],true,[new(30,120,start.AddMinutes(1),Guid.NewGuid())]);
 var path="/api/exercise/records/"+id;
 void Check(bool ok,string name){if(!ok)throw new Exception(name);}
 Check((await anonymous.GetAsync("/api/exercise/records")).StatusCode==HttpStatusCode.Unauthorized,"anonymous denied");
 Check((await owner.PutAsJsonAsync(path,record)).IsSuccessStatusCode,"create completed record");
 Check((await owner.PutAsJsonAsync(path.ToUpperInvariant().Replace("/API/EXERCISE/RECORDS/","/api/exercise/records/"),record)).IsSuccessStatusCode,"UUID variants and upload retry are idempotent");
 Check((await other.GetAsync(path)).StatusCode==HttpStatusCode.NotFound,"owner isolation");
 var restored=await owner.GetFromJsonAsync<ExerciseEndpoints.Record>(path);Check(restored?.Route?.Length==1 && restored.Intervals.Length==2,"cross-device full record read");
 Check((await owner.PutAsJsonAsync(path,record with {Kind="changed"})).StatusCode==HttpStatusCode.Conflict,"immutable record conflict preserves data");
 Check((await owner.PutAsJsonAsync(path,record with {EndedAt=null})).StatusCode==HttpStatusCode.BadRequest,"active incomplete record rejected");
 Check((await owner.PutAsJsonAsync(path,record with {Route=[new(30,120,start.AddMinutes(15),Guid.NewGuid())]})).StatusCode==HttpStatusCode.BadRequest,"paused location rejected");
 Check((await owner.PutAsJsonAsync(path,record with {Route=[new(91,120,start.AddMinutes(1),Guid.NewGuid())]})).StatusCode==HttpStatusCode.BadRequest,"invalid coordinate rejected");
 Check((await owner.DeleteAsync(path)).IsSuccessStatusCode && (await owner.DeleteAsync(path)).IsSuccessStatusCode,"delete retry idempotent");
 Check((await owner.GetAsync(path)).StatusCode==HttpStatusCode.NotFound,"deleted coordinates removed");
 Check((await owner.PutAsJsonAsync(path,record)).StatusCode==HttpStatusCode.Conflict,"offline upload cannot resurrect deletion");
 var page=await owner.GetFromJsonAsync<JsonElement>("/api/exercise/records");Check(page.GetProperty("records")[0].GetProperty("deleted").GetBoolean(),"other device sees tombstone");
 var isolated=await other.GetFromJsonAsync<JsonElement>("/api/exercise/records");Check(isolated.GetProperty("records").GetArrayLength()==0,"list owner isolation");
 // A fresh repository instance sees durable state, independent of process memory.
 var fresh=new ExerciseRecordStore(folder);Check(fresh.Read("owner",id)==null,"restart retains tombstone");
 Console.WriteLine("PASS: 15 exercise sync HTTP/storage checks");
} finally {await app.StopAsync();await app.DisposeAsync();if(Directory.Exists(folder))Directory.Delete(folder,true);}
sealed class TestAuth(IOptionsMonitor<AuthenticationSchemeOptions> options,ILoggerFactory logger,UrlEncoder encoder):AuthenticationHandler<AuthenticationSchemeOptions>(options,logger,encoder){
 protected override Task<AuthenticateResult> HandleAuthenticateAsync(){var id=Request.Headers["X-Test-User"].ToString();return Task.FromResult(id.Length==0?AuthenticateResult.NoResult():AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub",id)],"Test")),"Test")));}
}
