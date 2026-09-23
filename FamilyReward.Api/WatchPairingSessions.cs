using System.Security.Cryptography;
using System.Text;
using QRCoder;

// Short-lived display challenges are not device bindings. Restarting the service expires
// pending codes; approved devices remain in watch_device_bindings and recover by token.
public sealed class WatchPairingSessions(TimeProvider? clock = null)
{
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private readonly Dictionary<string, Session> sessions = new();
    private readonly SemaphoreSlim gate = new(1, 1);
    public sealed record Challenge(string Code, string DeviceToken, DateTimeOffset ExpiresAt, string VerificationUrl, bool[][] QrModules);
    public sealed class Session(string code, string tokenHash, DateTimeOffset expiresAt, string name, string platform, string? previousTokenHash)
    {
        public string Code { get; } = code;
        public string TokenHash { get; } = tokenHash;
        public DateTimeOffset ExpiresAt { get; } = expiresAt;
        public string DeviceName { get; } = name;
        public string Platform { get; } = platform;
        public string? PreviousTokenHash { get; } = previousTokenHash;
        public string? Owner { get; set; }
        public int ChildId { get; set; }
        public int? DeviceId { get; set; }
    }
    public static string Hash(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();
    public static string Normalize(string code) => code.Trim().Replace("-", "").Replace(" ", "").ToUpperInvariant();
    public async Task<Challenge?> Start(string origin, string name, string platform, string? previousTokenHash = null)
    {
        await gate.WaitAsync();
        try
        {
            foreach (var item in sessions.Where(x => x.Value.ExpiresAt <= clock.GetUtcNow()).ToArray()) sessions.Remove(item.Key);
            if (sessions.Count >= 1024) return null;
            const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
            string code;
            do { code = string.Concat(Enumerable.Range(0, 8).Select(_ => alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)])); }
            while (sessions.ContainsKey(code));
            var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
            var expiry = clock.GetUtcNow().AddMinutes(10);
            var url = origin.TrimEnd('/') + "/children?watchCode=" + code;
            using var generator = new QRCodeGenerator();
            using var qr = generator.CreateQrCode(url, QRCodeGenerator.ECCLevel.M);
            sessions.Add(code, new Session(code, Hash(token), expiry, name, platform, previousTokenHash));
            return new(code, token, expiry, url, qr.ModuleMatrix.Select(row => row.Cast<bool>().ToArray()).ToArray());
        }
        finally { gate.Release(); }
    }
    public async Task<bool> IsPending(string token)
    {
        await gate.WaitAsync();
        try { return sessions.Values.Any(x => x.TokenHash == Hash(token) && x.ExpiresAt > clock.GetUtcNow() && x.DeviceId == null); }
        finally { gate.Release(); }
    }
    public async Task<(int? DeviceId, string? Error)> Approve(string code, string owner, int childId, Func<Session, Task<int>> bind)
    {
        await gate.WaitAsync();
        try
        {
            if (!sessions.TryGetValue(Normalize(code), out var session) || session.ExpiresAt <= clock.GetUtcNow())
                return (null, "设备码无效或已过期，请在手表上刷新设备码");
            if (session.DeviceId != null)
                return session.Owner == owner && session.ChildId == childId
                    ? (session.DeviceId, null) : (null, "设备码已使用，请勿重复绑定");
            var id = await bind(session);
            session.Owner = owner; session.ChildId = childId; session.DeviceId = id;
            return (id, null);
        }
        finally { gate.Release(); }
    }
}
