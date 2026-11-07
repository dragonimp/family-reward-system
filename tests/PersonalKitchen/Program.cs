using Goldfish.WebAppSdk;
using System.Text;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using Npgsql;

var cs=Environment.GetEnvironmentVariable("KITCHEN_TEST_DSN")??throw new Exception("Isolated database required");
void Check(bool ok,string label){if(!ok)throw new Exception(label);Console.WriteLine("PASS "+label);}
var builder=WebApplication.CreateBuilder();builder.WebHost.UseUrls("http://127.0.0.1:0");builder.Logging.ClearProviders();
builder.Services.AddAuthentication("test").AddScheme<AuthenticationSchemeOptions,Identity>("test",_=>{});builder.Services.AddAuthorization();builder.Services.AddRateLimiter(o=>o.AddFixedWindowLimiter("kitchen-upload",v=>{v.PermitLimit=100;v.Window=TimeSpan.FromMinutes(1);}));
await using var app=builder.Build();app.UseAuthentication();app.UseAuthorization();app.UseRateLimiter();app.MapPersonalKitchen(cs,r=>r.HttpContext.User.Identity?.IsAuthenticated==true?new KitchenActor(r.HttpContext.User.FindFirst(ClaimTypes.NameIdentifier)!.Value,"test"):null);await app.StartAsync();
using var client=new HttpClient{BaseAddress=new Uri(app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single())};
async Task<HttpResponseMessage> Send(string method,string path,object? body=null,string? owner="alice"){using var req=new HttpRequestMessage(new HttpMethod(method),"/api/kitchen/"+path);if(owner!=null)req.Headers.Add("X-Test-User",owner);if(body!=null)req.Content=JsonContent.Create(body);return await client.SendAsync(req);}
async Task<JsonObject> Data(HttpResponseMessage r){var text=await r.Content.ReadAsStringAsync();if(!r.IsSuccessStatusCode)throw new Exception($"{r.StatusCode}: {text}");return JsonNode.Parse(string.IsNullOrWhiteSpace(text)?"{}":text)!.AsObject();}
async Task<int> Count(Guid id){var data=await Data(await Send("GET",$"recipes/{id}?kind=private"));return data["madeCount"]!.GetValue<int>();}
var id=Guid.NewGuid();var draft=new {name="测试蛋炒饭",ingredients=new[]{new{name="米饭",quantity="1",unit="碗"}},steps=new[]{new{number=1,action="炒熟",ingredients=new[]{"米饭"},duration="5分钟",heat="中火",instruction="翻炒至充分热透。",notes="注意食品安全"}}};
Check((await Send("GET","recipes",owner:null)).StatusCode==HttpStatusCode.Unauthorized,"anonymous access rejected");
Check((await Send("PUT",$"recipes/{id}",new{recipe=draft,confirmed=false})).StatusCode==HttpStatusCode.BadRequest,"explicit confirmation required");
await Data(await Send("PUT",$"recipes/{id}",new{recipe=draft,confirmed=true,version=0,sourceText="原创测试"}));
await Data(await Send("PUT",$"recipes/{id}",new{recipe=draft,confirmed=true,version=0,sourceText="原创测试"}));
Check((await Send("GET",$"recipes/{id}?kind=private",owner:"bob")).StatusCode==HttpStatusCode.NotFound,"other user cannot read private recipe");
Check((await Send("DELETE",$"recipes/{id}",owner:"bob")).StatusCode==HttpStatusCode.NotFound,"other user cannot delete private recipe");
var lower=await (await Send("GET",$"recipes/{id:D}?kind=private")).Content.ReadAsStringAsync();var upper=await (await Send("GET",$"recipes/{id.ToString().ToUpperInvariant()}?kind=private")).Content.ReadAsStringAsync();Check(lower==upper,"UUID variants resolve same private recipe");
await Data(await Send("PUT",$"recipes/{id}/relationship",new{kind="private",favorite=false,starred=true}));var starred=await Data(await Send("GET","recipes?filter=starred"));Check(starred["items"]!.AsArray().Count==1&&await Count(id)==0,"star allowed without any cooking record");
Check((await Data(await Send("GET","recipes",owner:"bob")))["items"]!.AsArray().Count==0,"personal lists isolated");
var media=Guid.NewGuid();var bytes=File.ReadAllBytes(Environment.GetEnvironmentVariable("KITCHEN_TEST_IMAGE")!);
Check((await Send("POST","media",new{id=media,purpose="recipe",base64=Convert.ToBase64String(new byte[]{1,2,3})})).StatusCode==HttpStatusCode.BadRequest,"invalid image rejected");
await Data(await Send("POST","media",new{id=media,purpose="recipe",base64=Convert.ToBase64String(bytes)}));
Check((await Send("GET",$"media/{media}",owner:"bob")).StatusCode==HttpStatusCode.NotFound,"private original image is owner-only");
Check((await Send("GET",$"media/{media}")).Content.Headers.ContentType?.MediaType=="image/jpeg","original is authenticated JPEG");
var task=Guid.NewGuid();await Data(await Send("POST","recognitions",new{id=task,mediaId=media}));await Data(await Send("POST","recognitions",new{id=task,mediaId=media}));Check((await Send("GET",$"recognitions/{task}",owner:"bob")).StatusCode==HttpStatusCode.NotFound,"recognition jobs isolated");Check((await Data(await Send("GET","recognitions")))["items"]!.AsArray().Count==1,"recognition enqueue is idempotent");
using(var transport=new VisionFixture())using(var http=new HttpClient(transport)){
    var orbit=new OrbitWebAppClient(http,new OrbitWebAppOptions{ApplicationId="family-reward",WebAppBotId="test",BaseAddress=new Uri("https://fixture.invalid")});
    var worker=new KitchenRecognitionWorker(cs,(_,_)=>Task.FromResult((orbit,1,"test")),Microsoft.Extensions.Logging.Abstractions.NullLogger<KitchenRecognitionWorker>.Instance);
    Check(await worker.RunOne(CancellationToken.None),"worker claims queued recognition");
    var result=await Data(await Send("GET",$"recognitions/{task}"));Check(result["state"]!.ToString()=="completed"&&result["result"]?["draft"]?["ingredients"]?[0]?["quantity"]?.ToString()=="1","Orbit SDK SSE result becomes structured editable draft");
    Check(transport.SawPrivateDataUrl&&transport.Stopped&&transport.Archived,"vision gets private attachment and dedicated session is stopped and archived");
    Check((await Data(await Send("GET","recipes")))["items"]!.AsArray().Count==1,"recognition never automatically saves a recipe");
    Check(!await worker.RunOne(CancellationToken.None),"completed task is not generated again");
    var failedTask=Guid.NewGuid();await Data(await Send("POST","recognitions",new{id=failedTask,mediaId=media}));transport.Fail=true;await worker.RunOne(CancellationToken.None);Check((await Data(await Send("GET",$"recognitions/{failedTask}")))["state"]!.ToString()=="failed","provider error persists recoverable failure without saving recipe");
}
var photo=Guid.NewGuid();await Data(await Send("POST","media",new{id=photo,purpose="checkin",base64=Convert.ToBase64String(bytes)}));
var action=Guid.NewGuid();var checkin=new{recipeId=id,kind="private",mediaId=photo,cookedOn="2026-11-08",note="当地日历日期"};
var responses=await Task.WhenAll(Enumerable.Range(0,8).Select(_=>Send("PUT",$"checkins/{action}",checkin)));foreach(var r in responses)await Data(r);Check(await Count(id)==1,"concurrent same checkin counts once");
Check((await Send("PUT",$"checkins/{action}",new{recipeId=id,kind="private",mediaId=photo,cookedOn="2026-11-09",note=""})).StatusCode==HttpStatusCode.Conflict,"same operation cannot change payload");
await Data(await Send("PUT",$"checkins/{Guid.NewGuid()}",checkin));Check(await Count(id)==2,"different cooking action increases count");
await Data(await Send("DELETE",$"checkins/{action}"));Check(await Count(id)==1,"deleting checkin decreases count");Check((await Send("PUT",$"checkins/{action}",checkin)).StatusCode==HttpStatusCode.Conflict,"deleted action cannot resurrect from retry");
Check((await Data(await Send("GET","checkins",owner:"bob")))["items"]!.AsArray().Count==0,"checkin photos/history isolated");
Check((await Send("PUT",$"checkins/{Guid.NewGuid()}",checkin,owner:"bob")).StatusCode==HttpStatusCode.NotFound,"another user cannot link private recipe or photo");
await using(var c=new NpgsqlConnection(cs)){await c.OpenAsync();await using var q=new NpgsqlCommand("SELECT id FROM kitchen_recipes WHERE published LIMIT 1",c);var publicId=(Guid)(await q.ExecuteScalarAsync())!;await Data(await Send("PUT",$"recipes/{publicId}/relationship",new{kind="public",favorite=true,starred=true}));Check((await Send("PUT",$"recipes/{publicId}",new{recipe=draft,confirmed=true,version=0})).StatusCode==HttpStatusCode.Conflict,"private creation cannot overwrite public recipe");}
var recipes=await Data(await Send("GET","recipes"));Check(recipes["items"]!.AsArray().Count==2,"public favorite references body without private duplication");
await Data(await Send("DELETE",$"recipes/{id}"));Check((await Send("GET",$"recipes/{id}?kind=private")).StatusCode==HttpStatusCode.NotFound,"private delete hides recipe");Check((await Data(await Send("GET","cooked")))["items"]!.AsArray().Count==1,"cooking history survives recipe deletion");
await app.StopAsync();Console.WriteLine("Personal kitchen PostgreSQL HTTP checks complete");
sealed class Identity(IOptionsMonitor<AuthenticationSchemeOptions> o,ILoggerFactory l,UrlEncoder e):AuthenticationHandler<AuthenticationSchemeOptions>(o,l,e){protected override Task<AuthenticateResult> HandleAuthenticateAsync(){var name=Request.Headers["X-Test-User"].ToString();return Task.FromResult(name.Length==0?AuthenticateResult.NoResult():AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier,name)],"test")),"test")));}}

sealed class VisionFixture:HttpMessageHandler {
 public bool SawPrivateDataUrl,Stopped,Archived,Fail;
 protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage req,CancellationToken ct){
  var path=req.RequestUri!.AbsolutePath;
  if(path.EndsWith("/stream")){
   var body=JsonNode.Parse(await req.Content!.ReadAsStringAsync(ct))!;SawPrivateDataUrl=body["attachments"]?[0]?["dataUrl"]?.ToString().StartsWith("data:image/jpeg;base64,")==true;
   if(Fail)return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
   var draft=new{draft=new{name="转录测试",ingredients=new[]{new{name="米饭",quantity=1,unit="碗"}},steps=new[]{new{number=5,instruction="充分热透"}},duration=(int?)null,servings=(int?)null},uncertainFields=new[]{"火候"}};
   var frame=System.Text.Json.JsonSerializer.Serialize(new{type="stream.delta",payload=new{channel="content",delta=System.Text.Json.JsonSerializer.Serialize(draft)}});
   return new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent("data: "+frame+"\n\ndata: [DONE]\n\n",Encoding.UTF8,"text/event-stream")};
  }
  if(path.EndsWith("/stop"))Stopped=true;
  if(req.Method==HttpMethod.Put)Archived=true;
  return new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent(path=="/api/webapp/sessions"?"{\"id\":\"fixture-session\",\"agentId\":1}":"{}",Encoding.UTF8,"application/json")};
 }
}
