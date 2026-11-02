using System.Net;
using System.Net.Http.Json;

internal static class PublicActivityIntroduction
{
    private sealed record Introduction(string Title, string? Description, DateTimeOffset? StartsAt);

    public static void MapPublicActivityIntroduction(this WebApplication app)
    {
        app.MapGet("/api/dear/public/activities/{tenantId:guid}/{activityId:guid}", async (
            Guid tenantId, Guid activityId, HttpContext context, IConfiguration configuration,
            IHttpClientFactory clients, CancellationToken ct) =>
        {
            if (!Uri.TryCreate(configuration["LinkoSocial:BackendOrigin"], UriKind.Absolute, out var backend) ||
                !(backend.Scheme == "https" || backend.Scheme == "http" && backend.IsLoopback) ||
                backend.UserInfo.Length != 0 || backend.AbsolutePath != "/" || backend.Query.Length != 0 || backend.Fragment.Length != 0)
                return Results.StatusCode(503);
            using var response = await clients.CreateClient("dear-social-api").GetAsync(
                new Uri(backend, $"/api/public/activities/{tenantId:D}/{activityId:D}"), ct);
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
            var nonce = Guid.NewGuid().ToString("N");
            context.Response.Headers.CacheControl = "no-store";
            context.Response.Headers.XContentTypeOptions = "nosniff";
            context.Response.Headers["Referrer-Policy"] = "no-referrer";
            context.Response.Headers.ContentSecurityPolicy = $"default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-{nonce}'; base-uri 'none'; frame-ancestors 'none'";
            return Results.Content($$"""
                <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
                <title>{{title}} · Linko Moment</title><meta property="og:title" content="{{title}}"><meta property="og:type" content="website">
                <meta property="og:description" content="{{description}}"><meta name="description" content="{{description}}">
                <style>body{font-family:system-ui,sans-serif;background:#f4f7f5;color:#183a31;margin:0;padding:24px}main{max-width:680px;margin:8vh auto;background:white;border-radius:20px;padding:32px}h1{overflow-wrap:anywhere}p{white-space:pre-wrap;line-height:1.8}a{display:inline-block;padding:12px 20px;background:#126b51;color:white;border-radius:10px;text-decoration:none}small{display:block;margin-top:20px;color:#687b73}</style></head>
                <body><main><span>Linko Moment · 活动介绍</span><h1>{{title}}</h1><p>{{description}}</p><p><time datetime="{{date}}"></time></p>
                <a href="{{enter}}">进入活动</a>
                <small>活动介绍公开可见。进入活动查看照片、动态和成员时，需要登录并验证访问权限。</small></main>
                <script nonce="{{nonce}}">const t=document.querySelector('time');if(t.dateTime)t.textContent=new Date(t.dateTime).toLocaleString()+'（当地时间）';</script></body></html>
                """, "text/html; charset=utf-8");
        }).AllowAnonymous();
    }
}
