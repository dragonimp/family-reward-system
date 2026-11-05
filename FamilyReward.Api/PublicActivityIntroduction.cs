using System.Net;
using System.Net.Http.Json;

internal static class PublicActivityIntroduction
{
    private sealed record Introduction(string Title, string? Description, DateTimeOffset? StartsAt, bool HasCover = false);

    public static void MapPublicActivityIntroduction(this WebApplication app)
    {
        app.MapGet("/api/dear/public/activities/{tenantId:guid}/{activityId:guid}/cover", async (
            Guid tenantId, Guid activityId, HttpResponse httpResponse, IConfiguration configuration, IHttpClientFactory clients, CancellationToken ct) =>
        {
            httpResponse.Headers.CacheControl = "no-store";
            httpResponse.Headers.XContentTypeOptions = "nosniff";
            if (!TryBackend(configuration, out var backend)) return Results.StatusCode(503);
            using var response = await clients.CreateClient("dear-social-api").GetAsync(
                new Uri(backend!, $"/api/public/activities/{tenantId:D}/{activityId:D}/cover"), ct);
            if (response.StatusCode == HttpStatusCode.NotFound) return Results.NotFound();
            if (!response.IsSuccessStatusCode || response.Content.Headers.ContentType?.MediaType != "image/jpeg") return Results.StatusCode(503);
            if (response.Content.Headers.ContentLength > 256 * 1024) return Results.StatusCode(503);
            var bytes = await response.Content.ReadAsByteArrayAsync(ct);
            return bytes.Length is > 0 and <= 256 * 1024 ? Results.File(bytes, "image/jpeg") : Results.StatusCode(503);
        }).AllowAnonymous();
        app.MapGet("/api/dear/public/activities/{tenantId:guid}/{activityId:guid}", async (
            Guid tenantId, Guid activityId, HttpContext context, IConfiguration configuration,
            IHttpClientFactory clients, CancellationToken ct) =>
        {
            if (!TryBackend(configuration, out var backend)) return Results.StatusCode(503);
            using var response = await clients.CreateClient("dear-social-api").GetAsync(
                new Uri(backend!, $"/api/public/activities/{tenantId:D}/{activityId:D}"), ct);
            if (response.StatusCode == HttpStatusCode.NotFound) return Results.NotFound();
            if (!response.IsSuccessStatusCode) return Results.StatusCode(503);
            var item = await response.Content.ReadFromJsonAsync<Introduction>(cancellationToken: ct);
            if (item is null) return Results.StatusCode(503);
            var title = WebUtility.HtmlEncode(item.Title);
            var description = WebUtility.HtmlEncode(item.Description ?? "");
            var date = item.StartsAt?.ToString("O") ?? "";
            var invite = context.Request.Query["invite"].ToString();
            var enter = string.IsNullOrEmpty(invite)
                ? $"/dear/spaces/{tenantId:D}/activities/{activityId:D}"
                : "/moment/?invite=" + Uri.EscapeDataString(invite);
            enter = WebUtility.HtmlEncode(enter);
            var appQuery = $"tenantId={tenantId:D}&activityId={activityId:D}" +
                (string.IsNullOrEmpty(invite) ? "" : "&invite=" + Uri.EscapeDataString(invite));
            var appLink = WebUtility.HtmlEncode("linkofamily://activity?" + appQuery);
            var smartLink = WebUtility.HtmlEncode("linkomoment://activity?" + appQuery);
            var coverPath = item.HasCover ? $"/api/dear/public/activities/{tenantId:D}/{activityId:D}/cover" : "/moment-share-default.svg";
            // Use the configured, verified public origin for crawler metadata; never trust the request Host.
            const string publicOrigin = "https://happylife.ai.impx.net";
            var imageUrl = publicOrigin + coverPath;
            var canonicalUrl = publicOrigin + $"/api/dear/public/activities/{tenantId:D}/{activityId:D}";
            var nonce = Guid.NewGuid().ToString("N");
            context.Response.Headers.CacheControl = "no-store";
            context.Response.Headers.XContentTypeOptions = "nosniff";
            context.Response.Headers["Referrer-Policy"] = "no-referrer";
            context.Response.Headers.ContentSecurityPolicy = $"default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; script-src 'nonce-{nonce}'; base-uri 'none'; frame-ancestors 'none'";
            return Results.Content($$"""
                <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
                <meta name="apple-itunes-app" content="app-id=6828813434, app-argument={{smartLink}}"><title>{{title}} · Linko Moment</title><meta property="og:title" content="{{title}}"><meta property="og:type" content="website">
                <link rel="icon" type="image/png" href="/moment-app-icon.png"><link rel="apple-touch-icon" href="/moment-app-icon.png">
                <meta property="og:site_name" content="Linko Moment"><meta property="og:url" content="{{canonicalUrl}}"><meta property="og:image" content="https://happylife.ai.impx.net/moment-app-icon.png"><meta property="og:image:alt" content="Linko Moment Logo"><meta property="og:image" content="{{imageUrl}}"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="{{imageUrl}}">
                <meta property="og:description" content="{{description}}"><meta name="description" content="{{description}}">
                <style>body{font-family:system-ui,sans-serif;background:#f4f7f5;color:#183a31;margin:0;padding:24px}main{max-width:680px;margin:8vh auto;background:white;border-radius:20px;padding:32px}h1{overflow-wrap:anywhere}p{white-space:pre-wrap;line-height:1.8}a{display:inline-block;padding:12px 20px;background:#126b51;color:white;border-radius:10px;text-decoration:none}.brand{display:flex;align-items:center;gap:12px}.brand img{width:48px;height:48px;border-radius:12px}.cover{display:block;width:100%;max-height:380px;aspect-ratio:16/9;object-fit:cover;border-radius:14px;margin:24px 0}.actions{display:flex;gap:12px;flex-wrap:wrap}.secondary{background:#e6f2ed;color:#126b51}.install{background:#fff;color:#126b51;border:1px solid #b7cec3}.wechat-guide{background:#edf6ff;border:1px solid #bdd8ed;border-radius:12px;padding:16px;margin:20px 0}.wechat-guide h2{font-size:18px;margin:0 0 8px}.wechat-guide p{margin:0}.wechat-guide .arrow{float:right;font-size:28px}small{display:block;margin-top:20px;color:#687b73}</style></head>
                <body><main><div class="brand"><img src="/moment-app-icon.png" alt="Linko Moment Logo" width="48" height="48"><span>Linko Moment · 活动介绍</span></div><img class="cover" src="{{coverPath}}" alt="{{title}} 活动封面" fetchpriority="high"><h1>{{title}}</h1><p>{{description}}</p><p><time datetime="{{date}}"></time></p>
                <aside id="wechat-guide" class="wechat-guide" hidden tabindex="-1" aria-labelledby="wechat-title"><span class="arrow" aria-hidden="true">↗</span><h2 id="wechat-title">请在系统浏览器中打开</h2><p>微信内无法直接打开 App 或安装测试版。请点击微信右上角“···”，选择“在浏览器中打开”（iPhone 可选择 Safari），然后点击“在 App 中打开”或“安装测试版”。也可直接继续网页版。</p></aside>
                <div class="actions"><a id="open-app" href="{{appLink}}">在 App 中打开</a>
                <a class="install" href="https://home.ai.impx.net/invite/TvXoL3UTV60fnciLC1bjISYx" rel="noreferrer">安装测试版</a><a class="secondary" href="{{enter}}">继续网页版 · 进入活动</a></div>
                <p class="install-help">尚未安装 App？可选择“安装测试版”，或继续网页版。<a class="install" href="https://apps.apple.com/app/id6828813434" rel="noreferrer">App Store 正式版</a>正式版当前在美区、港区等地区可用，中国大陆区暂不可用。</p>
                <p id="app-help" hidden>如果没有打开 App，可先安装 TestFlight 并接受测试邀请。安装后返回本页，再点“在 App 中打开”。微信内无法唤起时，可从右上角菜单选择在浏览器中打开；也可继续网页版。</p>
                <small>活动介绍公开可见。进入活动查看照片、动态和成员时，需要登录并验证访问权限。</small></main>
                <script nonce="{{nonce}}">const t=document.querySelector('time');if(t.dateTime)t.textContent=new Date(t.dateTime).toLocaleString()+'（当地时间）';const isWeChat=/MicroMessenger/i.test(navigator.userAgent);const guide=document.querySelector('#wechat-guide');guide.hidden=!isWeChat;document.querySelectorAll('#open-app,.install').forEach(link=>link.addEventListener('click',event=>{if(isWeChat){event.preventDefault();guide.hidden=false;guide.scrollIntoView({block:'center',behavior:'smooth'});guide.focus({preventScroll:true});return;}if(link.id==='open-app')setTimeout(()=>{if(!document.hidden)document.querySelector('#app-help').hidden=false;},1500);}));</script></body></html>
                """, "text/html; charset=utf-8");
        }).AllowAnonymous();
    }
    private static bool TryBackend(IConfiguration configuration, out Uri? backend) =>
        Uri.TryCreate(configuration["LinkoSocial:BackendOrigin"], UriKind.Absolute, out backend) &&
        (backend.Scheme == "https" || backend.Scheme == "http" && backend.IsLoopback) &&
        backend.UserInfo.Length == 0 && backend.AbsolutePath == "/" && backend.Query.Length == 0 && backend.Fragment.Length == 0;

}
