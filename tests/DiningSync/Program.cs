using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Options;
using LinkoFamily;

static void Check(bool value,string label){if(!value)throw new Exception(label);Console.WriteLine("PASS "+label);}
var builder=WebApplication.CreateBuilder(args);builder.WebHost.UseUrls("http://127.0.0.1:0");builder.Logging.ClearProviders();builder.Services.AddAuthentication("test").AddScheme<AuthenticationSchemeOptions,Identity>("test",_=>{});builder.Services.AddAuthorization();
await using var app=builder.Build();app.UseAuthentication();app.UseAuthorization();app.MapDiningAccounts(Environment.GetEnvironmentVariable("DINING_TEST_DSN")!,r=>{if(r.Headers.ContainsKey("X-Service"))return null;var owner=r.HttpContext.User.FindFirstValue(ClaimTypes.NameIdentifier);return Guid.TryParse(owner,out var id)?id.ToString("D"):owner;});await app.StartAsync();
var origin=new Uri(app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single());using var ios=new HttpClient{BaseAddress=origin};using var android=new HttpClient{BaseAddress=origin};var user=Guid.NewGuid();ios.DefaultRequestHeaders.Add("X-User",user.ToString().ToUpperInvariant());android.DefaultRequestHeaders.Add("X-User",user.ToString());
const string path="/api/dining/account";
async Task<JsonObject> Body(HttpResponseMessage r){var text=await r.Content.ReadAsStringAsync();if(!r.IsSuccessStatusCode)throw new Exception(r.StatusCode+text);return JsonNode.Parse(text)!.AsObject();}
async Task<JsonObject> Sync(HttpClient client,JsonObject local,JsonObject? baseline=null,Guid? operation=null)=>await Body(await client.PostAsJsonAsync(path+"/sync",new{operationId=operation??Guid.NewGuid(),archive=local,baseline}));
JsonObject Place(string id)=>new(){["id"]=id,["name"]="牛肉面 & 茶",["address"]="测试地址",["latitude"]=31.0,["longitude"]=121.0,["category"]="面馆",["provider"]="amap",["distanceMeters"]=100.0};
JsonObject Archive(params Guid[] ids){var a=DiningSyncMerge.Empty();foreach(var id in ids)a["history"]!.AsArray().Add(new JsonObject{["id"]=id.ToString().ToUpperInvariant(),["place"]=Place("restaurant-A"),["mood"]="automatic",["selectedAt"]="2026-11-09T14:15:16+09:00",["checkedIn"]=true});a["habits"]!["restaurant-A"]=new JsonObject{["selected"]=0,["eaten"]=0,["skipped"]=0,["checkIns"]=ids.Length};return a;}
JsonObject Data(JsonObject response)=>response["archive"]!.DeepClone().AsObject();
using(var anonymous=new HttpClient{BaseAddress=origin})Check((await anonymous.GetAsync(path)).StatusCode==HttpStatusCode.Unauthorized,"anonymous account access denied");
var empty=await Body(await ios.GetAsync(path));Check(empty["version"]!.GetValue<int>()==0,"empty read does not manufacture user records");
var visit=Guid.NewGuid();var local=Archive(visit);local["favorites"]!.AsArray().Add(Place("restaurant-A"));var operation=Guid.NewGuid();var first=await Sync(ios,local,operation:operation);var remote=Data(await Body(await android.GetAsync(path)));
Check(remote["history"]!.AsArray().Count==1 && remote["favorites"]!.AsArray().Count==1,"Android reads imported iOS records and favorites across GUID case variants");
Check(remote["history"]![0]!["selectedAt"]!.ToString()=="2026-11-09T05:15:16Z","device-local offset is stored as UTC");
var repeated=await Sync(android,local,operation:operation);Check(repeated["version"]!.ToString()==first["version"]!.ToString()&&Data(repeated)["habits"]!["restaurant-A"]!["checkIns"]!.GetValue<int>()==1,"lost response replay is idempotent");
var reused=local.DeepClone().AsObject();reused["favorites"]!.AsArray().Clear();Check((await android.PostAsJsonAsync(path+"/sync",new{operationId=operation,archive=reused})).StatusCode==HttpStatusCode.Conflict,"operation ID cannot be reused for different data");
var secondLegacy=Archive(visit,Guid.NewGuid());await Sync(android,secondLegacy);var union=Data(await Body(await ios.GetAsync(path)));Check(union["history"]!.AsArray().Count==2&&union["habits"]!["restaurant-A"]!["checkIns"]!.GetValue<int>()==2,"second device import preserves distinct visits without double counting shared history");
var baseIos=union.DeepClone().AsObject();var editIos=union.DeepClone().AsObject();editIos["favorites"]!.AsArray().Clear();await Sync(ios,editIos,baseIos);
await Sync(android,local);Check(Data(await Body(await ios.GetAsync(path)))["favorites"]!.AsArray().Count==0,"legacy offline import cannot resurrect an unfavorited restaurant");
var addBack=Data(await Body(await ios.GetAsync(path)));var addLocal=addBack.DeepClone().AsObject();addLocal["favorites"]!.AsArray().Add(Place("restaurant-A"));await Sync(ios,addLocal,addBack);Check(Data(await Body(await android.GetAsync(path)))["favorites"]!.AsArray().Count==1,"explicit refavorite clears its tombstone");
var common=Data(await Body(await ios.GetAsync(path)));var a=common.DeepClone().AsObject();var b=common.DeepClone().AsObject();a["favorites"]!.AsArray().Add(Place("restaurant-B"));b["favorites"]!.AsArray().Add(Place("restaurant-C"));await Task.WhenAll(Sync(ios,a,common),Sync(android,b,common));var joined=Data(await Body(await ios.GetAsync(path)));Check(joined["favorites"]!.AsArray().Count==3,"simultaneous device changes preserve both favorites");
var countBase=joined.DeepClone().AsObject();var countA=joined.DeepClone().AsObject();var countB=joined.DeepClone().AsObject();countA["habits"]!["restaurant-A"]!["skipped"]=1;countB["habits"]!["restaurant-A"]!["skipped"]=2;await Task.WhenAll(Sync(ios,countA,countBase),Sync(android,countB,countBase));Check(Data(await Body(await ios.GetAsync(path)))["habits"]!["restaurant-A"]!["skipped"]!.GetValue<int>()==3,"offline preference increments from both devices are accumulated");
var manual=Archive();manual["favorites"]!.AsArray().Add(Place("manual:"+visit.ToString().ToUpperInvariant()));manual["habits"]!["manual:"+visit.ToString().ToUpperInvariant()]=new JsonObject{["selected"]=0,["eaten"]=0,["skipped"]=0,["checkIns"]=0};var normalized=DiningSyncMerge.Normalize(manual);Check(normalized["favorites"]![0]!["id"]!.ToString()=="manual:"+visit.ToString(),"manual restaurant GUID identity normalizes without changing provider IDs");
var invalid=Archive(visit,visit);Check((await ios.PostAsJsonAsync(path+"/sync",new{operationId=Guid.NewGuid(),archive=invalid})).StatusCode==HttpStatusCode.BadRequest,"semantic duplicate UUIDs are rejected instead of overwritten");
var missingZone=Archive(Guid.NewGuid());missingZone["history"]![0]!["selectedAt"]="2026-11-09T10:00:00";Check((await ios.PostAsJsonAsync(path+"/sync",new{operationId=Guid.NewGuid(),archive=missingZone})).StatusCode==HttpStatusCode.BadRequest,"ambiguous server-local timestamp rejected");
using(var other=new HttpClient{BaseAddress=origin}){other.DefaultRequestHeaders.Add("X-User",Guid.NewGuid().ToString());Check(Data(await Body(await other.GetAsync(path)))["history"]!.AsArray().Count==0,"other accounts cannot read dining history");}
using(var service=new HttpClient{BaseAddress=origin}){service.DefaultRequestHeaders.Add("X-User",user.ToString());service.DefaultRequestHeaders.Add("X-Service","true");Check((await service.GetAsync(path)).StatusCode==HttpStatusCode.Unauthorized,"service identity cannot impersonate a dining account");}
Check((await ios.GetAsync(path)).Headers.CacheControl?.NoStore==true,"personal archive has no-store cache policy");
await app.StopAsync();
sealed class Identity(IOptionsMonitor<AuthenticationSchemeOptions> o,ILoggerFactory l,UrlEncoder e):AuthenticationHandler<AuthenticationSchemeOptions>(o,l,e){protected override Task<AuthenticateResult> HandleAuthenticateAsync(){var name=Request.Headers["X-User"].ToString();return Task.FromResult(name.Length==0?AuthenticateResult.NoResult():AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier,name)],"test")),"test")));}}
