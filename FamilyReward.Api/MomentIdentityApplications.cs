using System.Security.Claims;

internal static class MomentIdentityApplications
{
    internal const string Legacy = "happylife.ai";
    internal const string Moment = "linko-moment.ai";
    internal static Dictionary<string, string> HostClients => new(StringComparer.OrdinalIgnoreCase)
    {
        ["happylife.ai.impx.net"] = Legacy,
        ["happylife.ai.xmkurt.com"] = Moment
    };
    internal static string ClientForHost(string host) => HostClients.TryGetValue(host, out var client) ? client
        : (Environment.GetEnvironmentVariable("AGENTIDENTITY_CLIENT_ID") ?? Legacy).Trim();
    // The calling endpoint has already validated this principal through the official SDK.
    internal static string? SourceClient(ClaimsPrincipal principal)
    {
        if (principal.Identity?.IsAuthenticated != true || principal.HasClaim(c => c.Type == "token_use")) return null;
        var key = principal.FindFirst("app_id")?.Value;
        return key is Legacy or Moment ? key : null;
    }
}
