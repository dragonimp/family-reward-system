using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Options;

void Check(bool value,string label){if(!value)throw new Exception(label);Console.WriteLine("PASS "+label);}
var builder=WebApplication.CreateBuilder();builder.WebHost.UseUrls("http://127.0.0.1:0");builder.Logging.ClearProviders();builder.Services.AddAuthentication("test").AddScheme<AuthenticationSchemeOptions,Identity>("test",_=>{});builder.Services.AddAuthorization();
await using var app=builder.Build();app.UseAuthentication();app.UseAuthorization();app.MapModulePreferences(Environment.GetEnvironmentVariable("MODULE_TEST_DSN")!,r=>{if(r.Headers.ContainsKey("X-Service"))return null;var owner=r.HttpContext.User.FindFirstValue(ClaimTypes.NameIdentifier);return Guid.TryParse(owner,out var id)?id.ToString("D"):owner;});await app.StartAsync();
var origin=new Uri(app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single());
using var android=new HttpClient{BaseAddress=origin};using var ios=new HttpClient{BaseAddress=origin};var user=Guid.NewGuid();android.DefaultRequestHeaders.Add("X-User",user.ToString().ToUpperInvariant());ios.DefaultRequestHeaders.Add("X-User",user.ToString());
const string path="/api/user/module-preferences";
async Task<JsonObject> Body(HttpResponseMessage r){var data=await r.Content.ReadAsStringAsync();if(!r.IsSuccessStatusCode)throw new Exception(r.StatusCode+data);return JsonNode.Parse(data)!.AsObject();}
using(var anonymous=new HttpClient{BaseAddress=origin})Check((await anonymous.GetAsync(path)).StatusCode==HttpStatusCode.Unauthorized,"anonymous rejected");
var initial=await Body(await ios.GetAsync(path));Check(initial["initialized"]!.ToString()=="false"&&initial["sections"]!.AsObject().All(p=>p.Value!.GetValue<bool>()),"new account defaults show all five tabs including My");
var first=await Body(await ios.PostAsJsonAsync(path+"/bootstrap",new{sections=new{growth=false}}));Check(first["version"]!.GetValue<long>()==1&&!first["sections"]!["growth"]!.GetValue<bool>(),"first device imports explicit legacy choice");
var second=await Body(await android.PostAsJsonAsync(path+"/bootstrap",new{sections=new{growth=true,dining=false}}));Check(JsonNode.DeepEquals(first,second),"second device bootstrap cannot overwrite saved account settings");
var updated=await Body(await ios.PatchAsJsonAsync(path,new{key="growth",enabled=true,expectedVersion=1}));Check(updated["version"]!.GetValue<long>()==2,"version advances after explicit change");
var remote=await Body(await android.GetAsync(path));Check(remote["sections"]!["growth"]!.GetValue<bool>(),"Android reads iOS change across GUID case variants");
Check((await android.PatchAsJsonAsync(path,new{key="dining",enabled=false,expectedVersion=1})).StatusCode==HttpStatusCode.Conflict,"stale device cannot overwrite newer configuration");
var next=await Body(await android.PatchAsJsonAsync(path,new{key="dining",enabled=false,expectedVersion=2}));var read=await Body(await ios.GetAsync(path));Check(!read["sections"]!["dining"]!.GetValue<bool>()&&read["sections"]!["growth"]!.GetValue<bool>(),"iOS reads Android change without clearing other modules");
var replies=await Task.WhenAll(Enumerable.Range(0,8).Select(i=>ios.PatchAsJsonAsync(path,new{key="activities",enabled=false,expectedVersion=3})));Check(replies.Count(r=>r.IsSuccessStatusCode)==1&&replies.Count(r=>r.StatusCode==HttpStatusCode.Conflict)==7,"concurrent edits preserve one revision winner");
using(var other=new HttpClient{BaseAddress=origin}){other.DefaultRequestHeaders.Add("X-User","another-account");var state=await Body(await other.GetAsync(path));Check(!state["initialized"]!.GetValue<bool>()&&state["sections"]!["dining"]!.GetValue<bool>(),"switching accounts cannot inherit prior account settings");}
Check((await ios.PatchAsJsonAsync(path,new{key="my",enabled=false,expectedVersion=4})).StatusCode==HttpStatusCode.BadRequest,"My cannot be disabled");
Check((await ios.PostAsJsonAsync(path+"/bootstrap",new{sections=new{growth="false"}})).StatusCode==HttpStatusCode.BadRequest,"invalid boolean rejected");
Check((await ios.GetAsync(path)).Headers.CacheControl?.NoStore==true,"account responses are never publicly cached");
using(var service=new HttpClient{BaseAddress=origin}){service.DefaultRequestHeaders.Add("X-User",user.ToString());service.DefaultRequestHeaders.Add("X-Service","true");Check((await service.GetAsync(path)).StatusCode==HttpStatusCode.Unauthorized,"service identity cannot read human account preferences");}
await app.StopAsync();
sealed class Identity(IOptionsMonitor<AuthenticationSchemeOptions> o,ILoggerFactory l,UrlEncoder e):AuthenticationHandler<AuthenticationSchemeOptions>(o,l,e){protected override Task<AuthenticateResult> HandleAuthenticateAsync(){var name=Request.Headers["X-User"].ToString();return Task.FromResult(name.Length==0?AuthenticateResult.NoResult():AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier,name)],"test")),"test")));}}
