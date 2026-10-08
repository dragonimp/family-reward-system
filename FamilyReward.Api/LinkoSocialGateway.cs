using System.Net;
using System.Net.Http.Headers;
using AgentIdentity.NativeClient;

internal static class LinkoSocialGateway
{
    private static readonly string[] Methods = ["GET", "POST", "PATCH", "DELETE"];

    public static void MapLinkoSocialGateway(this WebApplication app)
    {
        app.MapMethods("/api/dear/social/{**path}", Methods, async (HttpContext context, string? path,
            IHttpClientFactory clients, IConfiguration configuration, CancellationToken ct) =>
        {
            if (!Allowed(context.Request.Method, path)) return Results.NotFound();
            var originText = configuration["LinkoSocial:Origin"];
            var loginText = configuration["LinkoSocial:LoginOrigin"];
            if (!Uri.TryCreate(originText, UriKind.Absolute, out var origin) || origin.Scheme != "https" ||
                !Uri.TryCreate(loginText, UriKind.Absolute, out var loginOrigin) || loginOrigin.Scheme != "https")
                return Results.Problem("Linko Social 服务地址未配置。", statusCode: 503);

            var authorization = context.Request.Headers.Authorization.ToString();
            var token = context.Items["AgentIdentity.RenewedAccessToken"] as string;
            token ??= authorization.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
                ? authorization[7..].Trim()
                : context.Request.Cookies[configuration["AGENTIDENTITY_COOKIE_NAME"]
                    ?? Environment.GetEnvironmentVariable("AGENTIDENTITY_COOKIE_NAME") ?? "happylife_access_token"];
            if (string.IsNullOrWhiteSpace(token)) return Results.Unauthorized();

            try
            {
                var serviceToken = await new NativeSsoClient(clients.CreateClient("dear-social-sso"))
                    .ExchangeAsync(loginOrigin, origin, token, ct);
                var destination = new Uri(origin, "/api/" + path + context.Request.QueryString);
                using var outgoing = new HttpRequestMessage(new HttpMethod(context.Request.Method), destination);
                outgoing.Headers.Authorization = new AuthenticationHeaderValue("Bearer", serviceToken);
                if (context.Request.ContentLength is > 0 || context.Request.Headers.ContainsKey("Transfer-Encoding"))
                {
                    outgoing.Content = new StreamContent(context.Request.Body);
                    if (MediaTypeHeaderValue.TryParse(context.Request.ContentType, out var contentType))
                        outgoing.Content.Headers.ContentType = contentType;
                }
                using var response = await clients.CreateClient("dear-social-api")
                    .SendAsync(outgoing, HttpCompletionOption.ResponseHeadersRead, ct);
                context.Response.StatusCode = (int)response.StatusCode;
                context.Response.Headers.CacheControl = "private, no-store";
                context.Response.Headers.XContentTypeOptions = "nosniff";
                if (response.Content.Headers.ContentType is { } type)
                    context.Response.ContentType = type.ToString();
                await response.Content.CopyToAsync(context.Response.Body, ct);
                return Results.Empty;
            }
            catch (HttpRequestException exception) when (exception.StatusCode == HttpStatusCode.Unauthorized)
            {
                return Results.Json(new { error = "用户中心登录已过期，请重新登录。" }, statusCode: 401);
            }
            catch (HttpRequestException exception) when (exception.StatusCode == HttpStatusCode.Forbidden)
            {
                return Results.Json(new { error = "用户中心尚未授权当前账号跨应用使用 Linko Social。" }, statusCode: 403);
            }
            catch (HttpRequestException)
            {
                return Results.Json(new { error = "Linko Social 暂时不可用，请稍后重试。" }, statusCode: 502);
            }
        }).RequireAuthorization();
    }

    private static bool Allowed(string method, string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        var s = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (s.Length == 1 && s[0] == "me") return method == "GET";
        if (s.Length == 1 && s[0] == "tenants") return method is "GET" or "POST";
        if (s.Length == 3 && s[0] == "tenants" && Guid.TryParse(s[1], out _) && s[2] == "activities")
            return method is "GET" or "POST";
        if (s.Length >= 4 && s[0] == "tenants" && Guid.TryParse(s[1], out _) &&
            s[2] == "activities" && Guid.TryParse(s[3], out _))
        {
            if (s.Length == 4) return method == "PATCH";
            if (s.Length == 5 && s[4] == "invites") return method == "GET";
            if (s.Length == 5 && s[4] == "moments") return method is "GET" or "POST";
            if (s.Length == 5 && s[4] == "members") return method == "GET";
            if (s.Length == 6 && s[4] == "moments" && Guid.TryParse(s[5], out _)) return method == "DELETE";
            if (s.Length == 6 && s[4] == "invites" && s[5] is "link" or "username") return method == "POST";
            if (s.Length == 8 && s[4] == "invites" && s[5] == "username" && s[7] == "accept" &&
                s[6].Length is > 0 and <= 200 && s[6].All(c => !char.IsControl(c) && c is not ('/' or '\\' or '?' or '#'))) return method == "POST";
            if (s.Length == 6 && s[4] == "live" && s[5] == "photos") return method == "GET";
            if (s.Length == 7 && s[4] == "native-photos" && Guid.TryParse(s[5], out _) && s[6] == "thumbnail") return method == "GET";
        }
        if (s.Length == 3 && s[0] == "invites" && s[1] == "username" && s[2] == "pending") return method == "GET";
        if (s.Length == 1 && s[0] == "relationships") return method == "GET";
        if (s.Length == 2 && s[0] == "relationships" && s[1] == "requests") return method == "POST";
        if (s.Length == 2 && s[0] == "relationships" && Guid.TryParse(s[1], out _)) return method == "DELETE";
        if (s.Length == 3 && s[0] == "relationships" && Guid.TryParse(s[1], out _) && s[2] == "accept") return method == "POST";
        if (s.Length == 4 && s[0] == "invites" && s[1] == "link" && s[3] == "accept" &&
            s[2].Length is > 0 and <= 128 && s[2].All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_')) return method == "POST";
        return false;
    }
}
