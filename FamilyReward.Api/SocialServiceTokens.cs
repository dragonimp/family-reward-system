using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AgentIdentity.NativeClient;
using AgentIdentity.Sdk;
using Microsoft.Extensions.Caching.Memory;

// Cache only short-lived User Center service tokens, scoped to the authenticated
// source token and target app. Concurrent previews share one SDK exchange.
internal sealed class SocialServiceTokens : IDisposable
{
    private readonly MemoryCache cache = new(new MemoryCacheOptions { SizeLimit = 512 });
    private readonly SemaphoreSlim exchange = new(1, 1);

    public async Task<string> GetAsync(string token, string application, AgentIdentityOptions identity,
        IHttpClientFactory clients, CancellationToken ct)
    {
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity.Authority + "\n" + identity.ClientId + "\n" + application + "\n" + token)));
        if (cache.TryGetValue<string>(key, out var cached)) return cached!;
        await exchange.WaitAsync(ct);
        try
        {
            if (cache.TryGetValue<string>(key, out cached)) return cached!;
            var result = await new NativeSsoClient(clients.CreateClient("dear-social-sso"))
                .ExchangeApplicationAsync(new Uri(identity.Authority), identity.ClientId, application, token, ct);
            var expires = Expires(result);
            var now = DateTimeOffset.UtcNow;
            if (expires > now.AddSeconds(30))
                cache.Set(key, result, new MemoryCacheEntryOptions { Size = 1, AbsoluteExpiration = expires.AddSeconds(-30) < now.AddMinutes(5) ? expires.AddSeconds(-30) : now.AddMinutes(5) });
            return result;
        }
        finally { exchange.Release(); }
    }

    private static DateTimeOffset Expires(string token)
    {
        try
        {
            var parts = token.Split('.');
            if (parts.Length != 3) return DateTimeOffset.MinValue;
            var body = parts[1].Replace('-', '+').Replace('_', '/');
            body = body.PadRight((body.Length + 3) / 4 * 4, '=');
            using var value = JsonDocument.Parse(Convert.FromBase64String(body));
            return DateTimeOffset.FromUnixTimeSeconds(value.RootElement.GetProperty("exp").GetInt64());
        }
        catch (Exception error) when (error is FormatException or JsonException or KeyNotFoundException or ArgumentOutOfRangeException or InvalidOperationException) { return DateTimeOffset.MinValue; }
    }
    public void Dispose() { cache.Dispose(); exchange.Dispose(); }
}
