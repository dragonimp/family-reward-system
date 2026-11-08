using System.Net;
using System.Text.Json;

internal static class AnonymousActivityMedia
{
    private static bool Token(string token) => token.Length == 64 && token.All(Uri.IsHexDigit);
    private static bool Backend(IConfiguration config, out Uri? backend) => Uri.TryCreate(config["LinkoSocial:BackendOrigin"], UriKind.Absolute, out backend)
        && (backend.Scheme == "https" || backend.Scheme == "http" && backend.IsLoopback) && backend.UserInfo.Length == 0 && backend.AbsolutePath == "/" && backend.Query.Length == 0 && backend.Fragment.Length == 0;
    public static void MapAnonymousActivityMedia(this WebApplication app)
    {
        app.MapMethods("/api/dear/public/media-shares/{token}/view", ["GET", "HEAD"], async (string token, HttpContext context, IConfiguration config, IHttpClientFactory clients, CancellationToken ct) => {
            context.Response.Headers.CacheControl = "no-store"; context.Response.Headers["Referrer-Policy"] = "no-referrer"; context.Response.Headers["X-Robots-Tag"] = "noindex, nofollow, noarchive";
            if (!Token(token) || !Backend(config, out var backend)) return Results.NotFound();
            using var response = await clients.CreateClient("dear-social-api").GetAsync(new Uri(backend!, "/api/public/media-shares/" + token), ct);
            if (response.StatusCode == HttpStatusCode.NotFound) return Results.Content("<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>分享已失效 · Linko Moment</title><p>链接已过期或已被撤销。</p>", "text/html; charset=utf-8", statusCode: 404);
            if (!response.IsSuccessStatusCode) return Results.StatusCode(503);
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
            var title = WebUtility.HtmlEncode(document.RootElement.GetProperty("title").GetString() ?? "活动照片与视频");
            var nonce = Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(16));
            context.Response.Headers.ContentSecurityPolicy = $"default-src 'self'; img-src 'self' data:; media-src 'self'; style-src 'unsafe-inline'; script-src 'nonce-{nonce}'; base-uri 'none'; frame-ancestors 'none'";
            using var reader = new StreamReader(typeof(AnonymousActivityMedia).Assembly.GetManifestResourceStream("MomentAnonymousMediaPage")!);
            var html = (await reader.ReadToEndAsync(ct)).Replace("%%TITLE%%", title).Replace("%%TOKEN%%", token).Replace("%%NONCE%%", nonce);
            return Results.Content(html, "text/html; charset=utf-8");
        }).AllowAnonymous();
        app.MapMethods("/api/dear/public/media-shares/{token}", ["GET"], async (string token, HttpContext context, IConfiguration config, IHttpClientFactory clients, CancellationToken ct) => {
            if (!Token(token) || !Backend(config, out var backend)) { context.Response.StatusCode = 404; return; }
            using var response = await clients.CreateClient("dear-social-api").GetAsync(new Uri(backend!, "/api/public/media-shares/" + token), ct);
            context.Response.StatusCode = (int)response.StatusCode; context.Response.Headers.CacheControl = "no-store"; context.Response.Headers["Referrer-Policy"] = "no-referrer";
            context.Response.ContentType = "application/json";
            await response.Content.CopyToAsync(context.Response.Body, ct);
        }).AllowAnonymous();
        app.MapMethods("/api/dear/public/media-shares/{token}/media/{photoId:guid}/{kind}", ["GET", "HEAD"], async (string token, Guid photoId, string kind, HttpContext context, IConfiguration config, IHttpClientFactory clients, CancellationToken ct) => {
            if (!Token(token) || kind is not ("thumbnail" or "original") || !Backend(config, out var backend)) { context.Response.StatusCode = 404; return; }
            using var request = new HttpRequestMessage(new HttpMethod(context.Request.Method), new Uri(backend!, $"/api/public/media-shares/{token}/media/{photoId:D}/{kind}"));
            if (context.Request.Headers.TryGetValue("Range", out var range)) request.Headers.TryAddWithoutValidation("Range", range.ToString());
            using var response = await clients.CreateClient("dear-social-api").SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            context.Response.StatusCode = (int)response.StatusCode; context.Response.Headers.CacheControl = "no-store"; context.Response.Headers.XContentTypeOptions = "nosniff"; context.Response.Headers["Referrer-Policy"] = "no-referrer";
            context.Response.ContentType = response.Content.Headers.ContentType?.ToString() ?? "application/octet-stream";
            context.Response.ContentLength = response.Content.Headers.ContentLength;
            if (response.Headers.AcceptRanges.Count > 0) context.Response.Headers.AcceptRanges = string.Join(",", response.Headers.AcceptRanges);
            if (response.Content.Headers.ContentRange != null) context.Response.Headers.ContentRange = response.Content.Headers.ContentRange.ToString();
            if (context.Request.Method != "HEAD") await response.Content.CopyToAsync(context.Response.Body, ct);
        }).AllowAnonymous();
    }
}
