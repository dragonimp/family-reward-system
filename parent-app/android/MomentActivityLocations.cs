using System.Text.Json;

namespace LinkoFamily;

// Foreground-only, explicit-consent lease. Leaving the module revokes the lease.
internal sealed class MomentActivityLocations(FamilyStore store)
{
    CancellationTokenSource? running;
    MomentScope? scope;
    string? lease;
    long account;
    public bool Sharing => running != null;
    public event Action<string>? Status;
    public async Task Start(MomentScope target)
    {
        await Stop(); account = store.SessionVersion; scope = target; var cancel = running = new CancellationTokenSource();
        _ = Loop(target, cancel);
    }
    public async Task Stop()
    {
        var old = running; running = null; old?.Cancel();
        var key = lease; lease = null; var target = scope; scope = null;
        if (key != null && target.HasValue && account == store.SessionVersion && store.Authenticated)
            try { await store.CallAsync(target.Value.Api + "/location-sharing?leaseId=" + Uri.EscapeDataString(key), HttpMethod.Delete); } catch { }
    }
    async Task Loop(MomentScope target, CancellationTokenSource cancel)
    {
        var expectedAccount = account; var terminalStatus = "";
        try {
            while (!cancel.IsCancellationRequested && expectedAccount == store.SessionVersion && store.Authenticated) {
                var point = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(GeolocationAccuracy.Medium, TimeSpan.FromSeconds(10)), cancel.Token);
                if (point == null || point.Accuracy is null or > 1000 || Math.Abs((DateTimeOffset.UtcNow - point.Timestamp).TotalSeconds) > 30) throw new FamilyApiException("尚未获取到准确位置，请稍后重试。");
                if (lease == null) {
                    var receipt = await store.CallAsync(target.Api + "/location-sharing", HttpMethod.Post, new { }, cancel.Token);
                    var issued = receipt.GetProperty("leaseId").GetString();
                    if (cancel.IsCancellationRequested || running != cancel || expectedAccount != store.SessionVersion) {
                        if (issued != null && expectedAccount == store.SessionVersion) _ = store.CallAsync(target.Api + "/location-sharing?leaseId=" + Uri.EscapeDataString(issued), HttpMethod.Delete);
                        break;
                    }
                    lease = issued;
                }
                await store.CallAsync(target.Api + "/location-sharing", HttpMethod.Put, new { leaseId = lease, latitude = point.Latitude, longitude = point.Longitude, accuracy = point.Accuracy, altitude = point.Altitude, observedAt = point.Timestamp.ToUniversalTime().ToString("O") }, cancel.Token);
                Status?.Invoke(""); await Task.Delay(5000, cancel.Token);
            }
        } catch (OperationCanceledException) { }
        catch { terminalStatus = "位置共享未完成，请检查位置权限和网络后重试。"; }
        finally { if (running == cancel) { await Stop(); Status?.Invoke(terminalStatus); } cancel.Dispose(); }
    }
    public static async Task CheckIn(FamilyStore store, Page owner, MomentScope target)
    {
        var account = store.SessionVersion; var id = Guid.NewGuid();
        try {
            var point = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(GeolocationAccuracy.Best, TimeSpan.FromSeconds(15)));
            if (point == null || point.Altitude == null || DateTimeOffset.UtcNow - point.Timestamp > TimeSpan.FromMinutes(2)) throw new FamilyApiException("未获得有效位置和海拔，请检查定位权限后重试。");
            var address = "";
            try { var p = (await Geocoding.Default.GetPlacemarksAsync(point))?.FirstOrDefault(); if (p != null) address = string.Join(" ", new[] { p.AdminArea, p.Locality, p.SubLocality, p.Thoroughfare, p.SubThoroughfare }.Where(s => !string.IsNullOrWhiteSpace(s)).Distinct()); } catch { }
            var note = await owner.DisplayPromptAsync("活动打卡", (address.Length > 0 ? address : "已获取当前位置") + $" · 海拔 {point.Altitude:0.#} 米", "确认打卡", "取消", placeholder:"备注（选填）", maxLength:1000);
            if (note == null || account != store.SessionVersion) return;
            // The same request body and operation ID are retained across a network retry.
            var payload = new { requestId = id, latitude = point.Latitude, longitude = point.Longitude, altitudeMeters = point.Altitude.Value, address, note, recordedAt = point.Timestamp.ToUniversalTime().ToString("O") };
            while (account == store.SessionVersion) {
                try { await store.CallAsync(target.Api + "/checkins", HttpMethod.Post, payload); return; }
                catch { if (!await owner.DisplayAlertAsync("打卡未确认", "网络异常，可使用同一次操作重试，避免重复打卡。", "重试", "取消")) return; }
            }
        } catch (Exception e) { await owner.DisplayAlertAsync("活动打卡", e is FamilyApiException ? e.Message : "定位失败，请检查权限后重试。", "知道了"); }
    }
}
