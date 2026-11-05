using System.Net;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;

var builder = WebApplication.CreateBuilder();
builder.WebHost.UseUrls("http://127.0.0.1:0");
builder.Configuration["LinkoSocial:BackendOrigin"] = "http://127.0.0.1:54321";
builder.Services.AddSingleton<IHttpClientFactory, Backend>();
var app = builder.Build();
app.MapPublicActivityIntroduction();
await app.StartAsync();
try
{
    using var client = new HttpClient { BaseAddress = new Uri(app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single()) };
    var tenant = Guid.NewGuid(); var activity = Guid.NewGuid();
    foreach (var id in new[] { activity.ToString().ToLowerInvariant(), activity.ToString().ToUpperInvariant() })
    {
        using var response = await client.GetAsync($"/api/dear/public/activities/{tenant}/{id}?invite=a%26b%3Cc");
        var html = await response.Content.ReadAsStringAsync();
        Check(response.StatusCode == HttpStatusCode.OK && response.Content.Headers.ContentType?.MediaType == "text/html", "anonymous introduction HTML");
        Check(html.Contains("&lt;script&gt;title&lt;/script&gt;") && !html.Contains("<script>title</script>"), "activity metadata is HTML encoded");
        Check(html.Contains("/moment/?invite=a%26b%3Cc") && html.Contains("进入活动"), "invitation retained only on explicit enter link");
        Check(html.Contains("在 App 中打开") && html.Contains("继续网页版") && html.Contains("安装测试版"), "app, browser and explicit beta installation choices");
        Check(html.Contains("linkofamily://activity?tenantId=" + tenant.ToString()) && html.Contains("activityId=" + activity.ToString()) && html.Contains("&amp;invite=a%26b%3Cc"), "app link retains typed activity and encoded invitation");
        Check(html.Contains("apple-itunes-app") && html.Contains("app-id=6828813434") && html.Contains("linkomoment://activity"), "system banner targets successor app");
        Check(html.Contains("https://home.ai.impx.net/invite/TvXoL3UTV60fnciLC1bjISYx") && !html.Contains("Linko MomentX") && !html.Contains("linkomomentx://"), "managed installation invitation without legacy prompt");
        Check(html.IndexOf("id=\"open-app\"", StringComparison.Ordinal) < html.IndexOf("class=\"install\"", StringComparison.Ordinal) && html.IndexOf("class=\"install\"", StringComparison.Ordinal) < html.IndexOf("class=\"secondary\"", StringComparison.Ordinal), "ordered app, installation and browser actions");
        Check(html.Contains("og:image") && html.Contains("moment-app-icon.png") && html.Contains("class=\"cover\""), "public share logo, crawler image and activity cover");
        Check(html.Contains("尚未安装 App") && html.Contains("https://apps.apple.com/app/id6828813434") && html.Contains("中国大陆区暂不可用"), "official store and explicit installation and region guidance");
        Check(html.Contains("id=\"wechat-guide\"") && html.Contains("微信右上角") && html.Contains("MicroMessenger") && html.Contains("event.preventDefault()"), "WeChat offers system browser guidance before app and install navigation");
        Check(html.Contains("datetime=\"2026-11-01T01:00:00.0000000+00:00\"") && html.Contains("toLocaleString"), "dates converted by browser timezone");
        Check(response.Headers.CacheControl?.NoStore == true && response.Headers.Contains("Content-Security-Policy"), "no-store and document protection");
    }
    using (var cover = await client.GetAsync($"/api/dear/public/activities/{tenant}/{activity}/cover"))
        Check(cover.StatusCode == HttpStatusCode.OK && cover.Content.Headers.ContentType?.MediaType == "image/jpeg" && cover.Headers.CacheControl?.NoStore == true, "public cover is bounded image response with no-store");
    Check((await client.GetAsync($"/api/dear/public/activities/{Guid.Empty}/{activity}")).StatusCode == HttpStatusCode.NotFound, "missing activity remains 404");
    Check((await client.GetAsync("/api/dear/public/activities/invalid/invalid")).StatusCode == HttpStatusCode.NotFound, "invalid UUID rejected");
    Console.WriteLine("PASS: 29 public activity introduction checks");
}
finally { await app.StopAsync(); await app.DisposeAsync(); }

static void Check(bool condition, string name) { if (!condition) throw new Exception(name); }
sealed class Backend : IHttpClientFactory
{
    public HttpClient CreateClient(string name) => new(new Transport());
    private sealed class Transport : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (request.Headers.Authorization != null) throw new Exception("Public introduction must not forward credentials");
            if (request.RequestUri!.AbsolutePath.Contains(Guid.Empty.ToString())) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            if (request.RequestUri.AbsolutePath.EndsWith("/cover")) {
                var content = new ByteArrayContent(new byte[] { 0xff, 0xd8, 0xff, 1 });
                content.Headers.ContentType = new("image/jpeg");
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("""{"title":"<script>title</script>","description":"A & B","startsAt":"2026-11-01T01:00:00Z","hasCover":true}""", System.Text.Encoding.UTF8, "application/json") });
        }
    }
}
