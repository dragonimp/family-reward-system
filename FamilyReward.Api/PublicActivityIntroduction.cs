using System.Net;
using System.Net.Http.Json;

internal static class PublicActivityIntroduction
{
    private sealed record Introduction(string Title, string? Description, DateTimeOffset? StartsAt, bool HasCover = false);

    public static void MapPublicActivityIntroduction(this WebApplication app)
    {
        app.MapGet("/api/dear/public/brand/icon.png", () => Results.Stream(
            typeof(PublicActivityIntroduction).Assembly.GetManifestResourceStream("MomentShareIcon")!, "image/png")).AllowAnonymous();
        app.MapGet("/api/dear/public/brand/default-cover.svg", () => Results.Stream(
            typeof(PublicActivityIntroduction).Assembly.GetManifestResourceStream("MomentShareDefaultCover")!, "image/svg+xml")).AllowAnonymous();
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
            var coverPath = item.HasCover ? $"/api/dear/public/activities/{tenantId:D}/{activityId:D}/cover" : "/api/dear/public/brand/default-cover.svg";
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
                <link rel="icon" type="image/png" href="/api/dear/public/brand/icon.png"><link rel="apple-touch-icon" href="/api/dear/public/brand/icon.png">
                <meta property="og:site_name" content="Linko Moment"><meta property="og:url" content="{{canonicalUrl}}"><meta property="og:image" content="https://happylife.ai.impx.net/api/dear/public/brand/icon.png"><meta property="og:image:alt" content="Linko Moment Logo"><meta property="og:image" content="{{imageUrl}}"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="{{imageUrl}}">
                <meta property="og:description" content="{{description}}"><meta name="description" content="{{description}}">
                <style>
                *{box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;background:#eef2ed;color:#1c332c;margin:0;padding:32px 20px 48px;background-image:radial-gradient(ellipse at 15% 0%,#d9e7dd 0,transparent 60%)}main{max-width:720px;margin:0 auto}a{color:inherit;text-decoration:none}button,a{-webkit-tap-highlight-color:transparent}a:focus-visible{outline:3px solid #e5ae57;outline-offset:4px}.brand{display:flex;align-items:center;gap:11px;margin:0 0 24px 4px}.brand img{width:44px;height:44px;border-radius:12px;box-shadow:0 3px 12px #193b2c12}.brand strong{display:block;font-size:17px;letter-spacing:.2px}.brand span{display:block;color:#718579;font-size:12px;margin-top:3px;letter-spacing:2px}.invitation{overflow:hidden;background:#fff;border:1px solid #ffffffcc;border-radius:28px;box-shadow:0 20px 65px #264b3512}.hero{position:relative;background:#dae6de}.cover{display:block;width:100%;aspect-ratio:16/9;max-height:400px;object-fit:cover}.hero-label{position:absolute;left:24px;bottom:20px;background:#fffef5ee;border:1px solid #ffffffa0;border-radius:50px;padding:8px 13px;font-size:11px;font-weight:600;letter-spacing:2px;color:#315744;backdrop-filter:blur(8px)}.content{padding:32px}.eyebrow{margin:0 0 12px;color:#7b8e7e;font-size:11px;font-weight:600;letter-spacing:3px}h1{font-family:"Songti SC","Noto Serif CJK SC",Georgia,serif;font-size:34px;line-height:1.35;letter-spacing:.2px;margin:0 0 18px;overflow-wrap:anywhere}.time-chip{display:inline-flex;align-items:center;gap:7px;color:#64786d;background:#f3f6f2;border-radius:8px;font-size:12px;padding:8px 10px;margin-bottom:18px}.time-chip svg{width:15px;height:15px}.description{white-space:pre-wrap;line-height:1.9;color:#65766d;font-size:15px;margin:0 0 28px;overflow-wrap:anywhere}.description:empty{display:none}.actions{display:grid;grid-template-columns:1fr 1fr;gap:10px}.actions a{display:flex;justify-content:center;align-items:center;gap:10px;padding:15px 10px;border-radius:13px;font-size:14px;font-weight:600;min-height:50px;transition:background .15s,transform .15s}.actions a:active{transform:scale(.98)}#open-app{grid-column:1/-1;background:#235e46;color:#fff;box-shadow:0 5px 14px #235e4620}#open-app:after{content:'↗';font-size:20px;font-weight:400}.actions .install{background:#f1f5ee;color:#365c46;border:1px solid #e3eade}.secondary{background:#fff;color:#718077;border:1px solid #e6eae4}.install-help{margin:20px 0 0;text-align:center;color:#89948a;font-size:12px;line-height:1.8}.store-link{color:#426e53;text-decoration:underline;text-underline-offset:3px;margin-left:5px}.region-note{display:block;font-size:11px;color:#98a197;margin-top:5px}#app-help{background:#f7f8f4;border-radius:10px;padding:12px;margin-bottom:0;font-size:12px;line-height:1.8;color:#6b796b}.wechat-guide{background:#f1f6ef;border:1px solid #d8e5d1;border-radius:13px;padding:16px;margin:0 0 20px;color:#47623f}.wechat-guide h2{font-size:15px;margin:0 0 8px}.wechat-guide p{font-size:12px;line-height:1.8;margin:0}.wechat-guide .arrow{float:right;font-size:28px}.privacy{display:block;text-align:center;font-size:11px;line-height:1.8;color:#92a092;padding:20px 28px 0}.footer{text-align:center;letter-spacing:3px;color:#a3afa1;font-size:10px;margin-top:28px}.brand img{object-fit:cover}[hidden]{display:none!important}@media(max-width:480px){body{padding:22px 14px 32px}.brand{margin-bottom:18px}.invitation{border-radius:22px}.content{padding:25px 22px}h1{font-size:29px}.hero-label{left:20px;bottom:16px}.actions a{font-size:13px}.privacy{padding:18px 10px 0} }
                </style></head>
                <body><main><header class="brand"><img src="/api/dear/public/brand/icon.png" alt="Linko Moment Logo" width="44" height="44"><div><strong>Linko Moment</strong><span>活动邀请</span></div></header>
                <article class="invitation"><section class="hero"><img class="cover" src="{{coverPath}}" alt="{{title}} 活动封面" fetchpriority="high"><span class="hero-label">MOMENTS TOGETHER</span></section>
                <section class="content"><p class="eyebrow">一起，留下美好时刻</p><h1>{{title}}</h1>
                <div class="time-chip"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><rect x="4" y="5" width="16" height="16" rx="3"/><path d="M8 3v5m8-5v5M4 11h16"/></svg><time datetime="{{date}}"></time></div><p class="description">{{description}}</p>
                <aside id="wechat-guide" class="wechat-guide" hidden tabindex="-1" aria-labelledby="wechat-title"><span class="arrow" aria-hidden="true">↗</span><h2 id="wechat-title">请在系统浏览器中打开</h2><p>点击微信右上角“···”，选择“在浏览器中打开”（iPhone 可选择 Safari），即可打开 App 或安装。也可直接继续网页版。</p></aside>
                <div class="actions"><a id="open-app" href="{{appLink}}">在 App 中打开</a><a class="install" href="https://home.ai.impx.net/invite/TvXoL3UTV60fnciLC1bjISYx" rel="noreferrer">安装测试版</a><a class="secondary" href="{{enter}}">继续网页版 · 进入活动</a></div>
                <p class="install-help">尚未安装 App？<a class="store-link install" href="https://apps.apple.com/app/id6828813434" rel="noreferrer">App Store 正式版 ↗</a><span class="region-note">正式版当前在美区、港区等地区可用，中国大陆区暂不可用。也可选择上方测试版或继续网页版。</span></p>
                <p id="app-help" hidden>如果没有打开 App，可先安装正式版或测试版，安装后返回本页再点“在 App 中打开”。微信内请通过右上角菜单在系统浏览器打开，也可继续网页版。</p>
                </section></article><small class="privacy">活动介绍与封面公开可见<br>查看完整照片、动态和成员时，需要登录并验证访问权限</small><p class="footer">LINKO MOMENT · SHARED WITH YOU</p></main>
                <script nonce="{{nonce}}">const t=document.querySelector('time');if(t.dateTime)t.textContent=new Date(t.dateTime).toLocaleString()+'（当地时间）';else if(t.parentElement)t.parentElement.hidden=true;document.querySelector('.cover')?.addEventListener('error',event=>{event.target.src='/api/dear/public/brand/default-cover.svg';},{once:true});const isWeChat=/MicroMessenger/i.test(navigator.userAgent);const guide=document.querySelector('#wechat-guide');guide.hidden=!isWeChat;document.querySelectorAll('#open-app,.install').forEach(link=>link.addEventListener('click',event=>{if(isWeChat){event.preventDefault();guide.hidden=false;guide.scrollIntoView({block:'center',behavior:'smooth'});guide.focus({preventScroll:true});return;}if(link.id==='open-app')setTimeout(()=>{if(!document.hidden)document.querySelector('#app-help').hidden=false;},1500);}));</script></body></html>
                """, "text/html; charset=utf-8");
        }).AllowAnonymous();
    }
    private static bool TryBackend(IConfiguration configuration, out Uri? backend) =>
        Uri.TryCreate(configuration["LinkoSocial:BackendOrigin"], UriKind.Absolute, out backend) &&
        (backend.Scheme == "https" || backend.Scheme == "http" && backend.IsLoopback) &&
        backend.UserInfo.Length == 0 && backend.AbsolutePath == "/" && backend.Query.Length == 0 && backend.Fragment.Length == 0;

}
