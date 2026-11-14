using System.Net.Http.Headers;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using MyVnc.Realtime.Client;

namespace LinkoFamily;

// Business adapter only: the shared Connect SDK owns bytes, resume and integrity.
internal sealed class MomentOriginals(FamilyStore store)
{
    private readonly Dictionary<(long, MomentScope, Guid), string> received = [];
    public event Action? Changed;
    public string? Cached(MomentFeedItem item) => store.Authenticated && received.TryGetValue((store.SessionVersion, item.Scope, item.Record.Id), out var file) && File.Exists(file) ? file : null;

    public async Task<string> DownloadAsync(MomentFeedItem item, Action<string> status, IProgress<double> progress, CancellationToken cancellationToken)
    {
        if (Cached(item) is { } local) return local;
        var session = store.SessionVersion;
        var subject = store.AccountProfile?.Subject ?? store.Profile?.Text("unifiedUserId");
        if (!store.Authenticated || string.IsNullOrWhiteSpace(subject)) throw new FamilyApiException("请先登录用户中心。");
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        lifetime.CancelAfter(TimeSpan.FromMinutes(30));
        var ct = lifetime.Token;
        var accountWatch = WatchAccountAsync(session, lifetime);
        Guid requestId = Guid.Empty;
        bool finished = false;
        try
        {
            status("正在创建下载请求…");
            var row = new MomentRecord(await store.CallAsync(item.Scope.Api + "/photo-requests", HttpMethod.Post,
                new { photoId = item.Record.Id, operationId = Guid.NewGuid(), transport = "connect-datachannel-v1" }, ct));
            requestId = row.Id;
            var path = $"/api/dear/social/photo-requests/{requestId:D}";
            var manifest = MomentOriginalContract.Manifest(row);
            var contentType = row.Text("contentType");
            var suffix = MomentOriginalContract.Suffix(contentType);
            if (manifest.Length > (contentType.StartsWith("video/", StringComparison.Ordinal) ? 500L : 50L) * 1024 * 1024)
                throw new FamilyApiException("原文件大小超出限制。");
            var account = Guid.TryParse(subject, out var id) ? id.ToString("D") : subject;
            var root = Path.Combine(FileSystem.CacheDirectory, "MomentOriginals", Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(account))), item.Scope.Tenant.ToString("D"), item.Scope.Activity.ToString("D"));
            Directory.CreateDirectory(root);
            // Only this account/scope's old received files are eligible for eviction.
            foreach (var old in Directory.EnumerateFiles(root))
                if (File.GetLastWriteTimeUtc(old) < DateTime.UtcNow.AddDays(-7)) { try { File.Delete(old); } catch (IOException) { } }
            var file = Path.Combine(root, $"{item.Record.Id:D}-{manifest.Sha256.ToLowerInvariant()}{suffix}");
            var partial = file + ".part";
            if (await VerifiedAsync(file, manifest, ct))
            {
                await store.CallAsync(path + "/cancel", HttpMethod.Post, new { }, ct);
            }
            else
            {
                row = new MomentRecord(await store.CallAsync(path, ct: ct));
                while (row.Text("status") == "pending_approval")
                {
                    status("等待分享者打开消息同意…");
                    CheckState(row, manifest);
                    await Task.Delay(TimeSpan.FromSeconds(2), ct);
                    row = new MomentRecord(await store.CallAsync(path, ct: ct));
                }
                CheckState(row, manifest);
                if (!row.Flag("serverCached"))
                {
                    status("已同意，正在连接原件设备…");
                    var config = new MomentRecord(await store.CallAsync("/api/dear/social/connect-configuration", ct: ct));
                    if (config.Text("transport") != "connect-datachannel-v1" || config.Text("apiPathPrefix") != "/api/dear/social" ||
                        !Uri.TryCreate(config.Text("origin"), UriKind.Absolute, out var origin) || origin.Scheme != "https" || origin.UserInfo.Length != 0 || origin.AbsolutePath != "/" || origin.Query.Length != 0 || origin.Fragment.Length != 0)
                        throw new FamilyApiException("Connect 服务配置无效。");
                    using var direct = CancellationTokenSource.CreateLinkedTokenSource(ct);
                    var cacheWatch = WatchCacheAsync(path, direct);
                    try
                    {
                        await using var transfer = new RealtimeFileTransfer();
                        await transfer.ReceiveAsync(partial, manifest,
                            async token => {
                                using var request = await AuthorizedAsync(new Uri(origin, path + "/connect/ice?role=receiver"), HttpMethod.Get, session, token);
                                request.Headers.TryAddWithoutValidation("Origin", origin.GetLeftPart(UriPartial.Authority));
                                using var client = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false });
                                using var response = await client.SendAsync(request, token); response.EnsureSuccessStatusCode();
                                return await response.Content.ReadAsStringAsync(token);
                            },
                            async token => {
                                using var request = await AuthorizedAsync(origin, HttpMethod.Get, session, token);
                                var socket = new ClientWebSocket();
                                try {
                                    socket.Options.SetRequestHeader("Authorization", request.Headers.Authorization!.ToString());
                                    socket.Options.SetRequestHeader("Origin", origin.GetLeftPart(UriPartial.Authority));
                                    await socket.ConnectAsync(new UriBuilder(origin) { Scheme = "wss", Path = path + "/connect/signal", Query = "role=receiver" }.Uri, token);
                                    return socket;
                                } catch { socket.Dispose(); throw; }
                            }, progress, direct.Token);
                    }
                    catch (Exception error) when (error is IOException or WebSocketException or OperationCanceledException or HttpRequestException)
                    {
                        ct.ThrowIfCancellationRequested();
                        row = new MomentRecord(await store.CallAsync(path, ct: ct)); CheckState(row, manifest);
                        if (!row.Flag("serverCached")) throw;
                    }
                    finally { direct.Cancel(); await cacheWatch; }
                }
                if (row.Flag("serverCached"))
                {
                    status("正在从服务器缓存接收原文件…");
                    using var request = await AuthorizedAsync(new Uri("https://happylife.ai.xmkurt.com" + path + "/relay"), HttpMethod.Get, session, ct);
                    await RealtimeFileRelay.ReceiveAsync(partial, manifest, request, ct);
                }
                ct.ThrowIfCancellationRequested();
                if (!await VerifiedAsync(partial, manifest, ct)) throw new FamilyApiException("原文件完整性校验失败，请重试。");
                await store.CallAsync(path + "/complete", HttpMethod.Post, new { }, ct);
                ct.ThrowIfCancellationRequested();
                File.Move(partial, file, true);
            }
            if (session != store.SessionVersion || !store.Authenticated) throw new OperationCanceledException();
            finished = true; received[(session, item.Scope, item.Record.Id)] = file;
            progress.Report(1); Changed?.Invoke(); return file;
        }
        finally
        {
            lifetime.Cancel(); await accountWatch;
            // Cancel only within the originating account; never issue a write as a new user.
            if (!finished && requestId != Guid.Empty && session == store.SessionVersion && store.Authenticated)
                try { using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5)); await store.CallAsync($"/api/dear/social/photo-requests/{requestId:D}/cancel", HttpMethod.Post, new { }, timeout.Token); } catch { }
        }
    }
    private async Task WatchAccountAsync(long session, CancellationTokenSource lifetime)
    {
        try { while (!lifetime.IsCancellationRequested) { if (session != store.SessionVersion || !store.Authenticated) { lifetime.Cancel(); return; } await Task.Delay(200, lifetime.Token); } }
        catch (OperationCanceledException) { }
    }
    private async Task WatchCacheAsync(string path, CancellationTokenSource direct)
    {
        try { while (!direct.IsCancellationRequested) { await Task.Delay(2000, direct.Token); var row = new MomentRecord(await store.CallAsync(path, ct: direct.Token)); if (row.Flag("serverCached")) { direct.Cancel(); return; } } }
        catch (OperationCanceledException) { }
        catch { /* Direct transport still reports its own errors; fallback rechecks authorization. */ }
    }
    private async Task<HttpRequestMessage> AuthorizedAsync(Uri uri, HttpMethod method, long session, CancellationToken ct)
    {
        var token = await store.GetIdentityTokenAsync(ct);
        if (session != store.SessionVersion || !store.Authenticated || string.IsNullOrEmpty(token)) throw new OperationCanceledException();
        var request = new HttpRequestMessage(method, uri); request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token); return request;
    }
    private static void CheckState(MomentRecord row, RealtimeFileManifest manifest)
    {
        if (manifest.ExpiresAt <= DateTimeOffset.UtcNow || row.Text("status") is "cancelled" or "expired" or "revoked" or "unavailable" or "failed")
            throw new FamilyApiException("本次分享已停止、已过期或不可用，请重新获取。");
    }
    private static async Task<bool> VerifiedAsync(string file, RealtimeFileManifest manifest, CancellationToken ct)
    {
        if (!File.Exists(file) || new FileInfo(file).Length != manifest.Length) return false;
        await using var stream = File.OpenRead(file);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, ct)).Equals(manifest.Sha256, StringComparison.OrdinalIgnoreCase);
    }
}
