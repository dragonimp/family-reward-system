using System.Net;
using System.Net.Http.Headers;
using System.Net.WebSockets;
using System.Security.Claims;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using AgentIdentity.Sdk;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Options;

var assertions = 0;
void Check(bool ok, string name) { if (!ok) throw new Exception(name); assertions++; }
string Address(WebApplication app) => app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
var downstreamBuilder = WebApplication.CreateBuilder();
downstreamBuilder.Logging.ClearProviders();
downstreamBuilder.WebHost.UseUrls("http://127.0.0.1:0");
await using var downstream = downstreamBuilder.Build();
downstream.UseWebSockets();
downstream.Map("/api/{**path}", async context => {
    if (context.Request.Headers.Authorization != "Bearer service-test") { context.Response.StatusCode = 401; return; }
    if (context.Request.Headers.Origin != "https://happylife.ai.impx.net") { context.Response.StatusCode = 403; return; }
    if (context.Request.Path.Value!.EndsWith("/signal")) {
        using var socket = await context.WebSockets.AcceptWebSocketAsync();
        var buffer = new byte[1024];
        var result = await socket.ReceiveAsync(buffer.AsMemory(), context.RequestAborted);
        await socket.SendAsync(buffer.AsMemory(0, result.Count), result.MessageType, result.EndOfMessage, context.RequestAborted);
        await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "done", context.RequestAborted);
    } else if (context.Request.Path == "/api/tenants") {
        context.Response.StatusCode = 403;
        await context.Response.WriteAsync("membership denied");
    } else {
        using var reader = new StreamReader(context.Request.Body);
        await context.Response.WriteAsJsonAsync(new { path = context.Request.Path.Value, query = context.Request.QueryString.Value,
            revision = context.Request.Headers["X-Photo-Revision"].ToString(), body = await reader.ReadToEndAsync() });
    }
});
await downstream.StartAsync();
var builder = WebApplication.CreateBuilder();
builder.Logging.ClearProviders();
builder.WebHost.UseUrls("http://127.0.0.1:0");
builder.Configuration.AddInMemoryCollection(new Dictionary<string,string?> {
    ["LinkoSocial:Origin"] = "https://happylife.ai.impx.net", ["LinkoSocial:BackendOrigin"] = Address(downstream), ["LinkoSocial:ApplicationKey"] = "linko.ai"
});
builder.Services.AddSingleton(new AgentIdentityOptions { Authority = "https://identity.example.test", ClientId = "happylife.ai", CookieName = "happylife_access_token" });
builder.Services.AddAuthentication("test").AddScheme<AuthenticationSchemeOptions, TestAuth>("test", _ => {});
builder.Services.AddAuthorization();
builder.Services.AddHttpClient("dear-social-sso").ConfigurePrimaryHttpMessageHandler(() => new ExchangeHandler());
builder.Services.AddHttpClient("dear-social-api").ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
await using var app = builder.Build();
app.UseWebSockets(); app.UseAuthentication(); app.UseAuthorization(); app.MapLinkoSocialGateway(); await app.StartAsync();
using var client = new HttpClient { BaseAddress = new Uri(Address(app)) };
Check((await client.GetAsync("/api/dear/social/me")).StatusCode == HttpStatusCode.Unauthorized, "anonymous must be rejected");
client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "family-test");
var config = JsonDocument.Parse(await client.GetStringAsync("/api/dear/social/connect-configuration")).RootElement;
Check(config.GetProperty("origin").GetString() == "https://happylife.ai.impx.net", "canonical origin");
Check(config.GetProperty("apiPathPrefix").GetString() == "/api/dear/social", "Connect path");
Check((await client.GetAsync("/api/dear/social/internal/atlas-release/version")).StatusCode == HttpStatusCode.NotFound, "internal controls blocked");
Check((await client.GetAsync("/api/dear/social/tenants")).StatusCode == HttpStatusCode.Forbidden, "membership rejection preserved");
var tenant = Guid.NewGuid(); var activity = Guid.NewGuid(); var photo = Guid.NewGuid(); var requestId = Guid.NewGuid();
var path = $"/api/dear/social/tenants/{tenant}/activities/{activity}/native-photos/{photo}/thumbnail";
using var upload = new HttpRequestMessage(HttpMethod.Put,path) { Content = new StringContent("preview") };
upload.Headers.Add("X-Photo-Revision", "sha-revision");
var reply = await client.SendAsync(upload); reply.EnsureSuccessStatusCode();
var echo = JsonDocument.Parse(await reply.Content.ReadAsStringAsync()).RootElement;
Check(echo.GetProperty("revision").GetString() == "sha-revision" && echo.GetProperty("body").GetString() == "preview", "preview upload and revision preserved");
var ice = await client.GetStringAsync($"/api/dear/social/photo-requests/{requestId}/connect/ice?role=receiver");
Check(ice.Contains("role=receiver"), "ICE role preserved");
using var socket = new ClientWebSocket();
socket.Options.SetRequestHeader("Authorization", "Bearer family-test");
await socket.ConnectAsync(new Uri(Address(app).Replace("http://","ws://") + $"/api/dear/social/photo-requests/{requestId}/connect/signal?role=receiver"), CancellationToken.None);
var payload = Encoding.UTF8.GetBytes("Connect signaling");
await socket.SendAsync(payload, WebSocketMessageType.Binary, true, CancellationToken.None);
var bytes = new byte[256]; var received = await socket.ReceiveAsync(bytes.AsMemory(), CancellationToken.None);
Check(received.MessageType == WebSocketMessageType.Binary && Encoding.UTF8.GetString(bytes,0,received.Count) == "Connect signaling", "bidirectional authorized WebSocket");
var closed = await socket.ReceiveAsync(bytes.AsMemory(), CancellationToken.None);
Check(closed.MessageType == WebSocketMessageType.Close, "close propagated");
await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure,"done",CancellationToken.None);
client.DefaultRequestHeaders.Authorization = null;
client.DefaultRequestHeaders.Add("Cookie", "happylife_access_token=family-test");
Check((await client.GetAsync("/api/dear/social/me")).IsSuccessStatusCode, "shared browser cookie");
Console.WriteLine($"PASS: {assertions} Moment gateway HTTP, identity exchange and WebSocket checks");

sealed class TestAuth(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder) {
 protected override Task<AuthenticateResult> HandleAuthenticateAsync() {
  var token = Request.Headers.Authorization.ToString() == "Bearer family-test" || Request.Cookies["happylife_access_token"] == "family-test";
  return Task.FromResult(token ? AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub","test")],"test")),"test")) : AuthenticateResult.NoResult());
 }
}
sealed class ExchangeHandler : HttpMessageHandler {
 protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken ct) {
  var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct)).RootElement;
  if (request.RequestUri!.AbsoluteUri != "https://identity.example.test/oauth/native-service-token" || request.Headers.Authorization?.ToString() != "Bearer family-test" || body.GetProperty("sourceClientId").GetString() != "happylife.ai" || body.GetProperty("targetClientId").GetString() != "linko.ai") throw new Exception("incorrect SDK application exchange");
  return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"access_token\":\"service-test\"}",Encoding.UTF8,"application/json") };
 }
}
