using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace LinkoFamily;

public sealed partial class ExercisePanel
{
    public sealed class WorkoutInterval
    {
        public DateTimeOffset Start { get; set; }
        public DateTimeOffset? End { get; set; }
        public int? Steps { get; set; }
        public double? DistanceMeters { get; set; }
    }
    public sealed record WorkoutPoint(double Latitude, double Longitude, DateTimeOffset RecordedAt, Guid Segment,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] double? AltitudeMeters = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] double? VerticalAccuracyMeters = null);
    private readonly FamilyStore api;
    private readonly string userID;
    private bool syncing;
    private CancellationTokenSource? locationCancellation;
    private readonly Label altitudeLabel = MomentStyle.Caption("海拔待获取");
    private static readonly JsonSerializerOptions Wire = new(JsonSerializerDefaults.Web);
    private bool OwnSession(long generation) => api.SessionVersion == generation && DiningAccount.Identity(api.Profile?.Text("unifiedUserId") ?? "") == DiningAccount.Identity(userID);
    private object WireRecord(Workout item) => item.SourceRecord is { } source ? source : JsonSerializer.SerializeToElement(new {
        id = item.SyncId, kind = item.Kind, startedAt = item.StartedAt, endedAt = item.EndedAt,
        intervals = item.Intervals, activity = item.Activity, activityText = item.ActivityText, routeEnabled = item.RouteEnabled || item.Route.Count > 0, route = item.Route
    }, Wire);
    private static string SharedText(Workout item)
    {
        if (item.ActivityText != null) return item.ActivityText;
        var elapsed = item.Intervals.Count > 0 && item.Intervals[0].Start == item.StartedAt ? item.Intervals.Sum(i => Math.Max(0, (i.End ?? i.Start).ToUnixTimeSeconds() - i.Start.ToUnixTimeSeconds())) : item.Seconds;
        var distance = item.DistanceOverride ?? (item.HasSteps ? item.Steps * item.StepLengthMeters : null);
        return ExerciseSummaryText.Format(item.Kind, elapsed, distance, item.HasSteps ? item.Steps : null, item.Route.Where(p => p.AltitudeMeters != null).Select(p => p.AltitudeMeters!.Value));
    }
    private async Task SyncAsync()
    {
        if (syncing || !readable) return;
        var generation = api.SessionVersion;
        if (!OwnSession(generation)) return;
        syncing = true; Update();
        try {
            foreach (var id in archive.PendingDeletions.ToArray()) {
                await api.CallAsync($"/api/exercise/records/{id:D}", HttpMethod.Delete);
                if (!OwnSession(generation)) return;
                archive.PendingDeletions.Remove(id); archive.Uploaded.Remove(id); Save();
            }
            var remote = new Dictionary<Guid, bool>(); string? cursor = null;
            do {
                var page = await api.CallAsync("/api/exercise/records" + (cursor == null ? "" : "?after=" + cursor));
                if (!OwnSession(generation)) return;
                foreach (var row in page.GetProperty("records").EnumerateArray()) remote[row.GetProperty("id").GetGuid()] = row.GetProperty("deleted").GetBoolean();
                var next = page.TryGetProperty("next", out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
                if (next != null && next == cursor) throw new InvalidDataException("运动同步分页无效。");
                cursor = next;
            } while (cursor != null);
            foreach (var deleted in remote.Where(x => x.Value)) { archive.History.RemoveAll(x => x.SyncId == deleted.Key); archive.Uploaded.Remove(deleted.Key); }
            Save();
            foreach (var item in archive.History.ToArray()) {
                if (item.EndedAt == null || item.Intervals.Count == 0 || item.Intervals[0].Start != item.StartedAt || archive.PendingDeletions.Contains(item.SyncId)) continue; // Preserve legacy duration-only records without inventing interval timestamps.
                if (!remote.ContainsKey(item.SyncId) || !archive.Uploaded.Contains(item.SyncId)) {
                    await api.CallAsync($"/api/exercise/records/{item.SyncId:D}", HttpMethod.Put, WireRecord(item));
                    if (!OwnSession(generation)) return;
                    if (!archive.Uploaded.Contains(item.SyncId)) archive.Uploaded.Add(item.SyncId); Save();
                }
            }
            foreach (var pair in remote.Where(x => !x.Value && !archive.History.Any(r => r.SyncId == x.Key))) {
                var raw = await api.CallAsync($"/api/exercise/records/{pair.Key:D}");
                if (!OwnSession(generation)) return;
                var intervals = JsonSerializer.Deserialize<List<WorkoutInterval>>(raw.GetProperty("intervals"), Wire) ?? [];
                var item = new Workout { Id = pair.Key, Kind = raw.GetProperty("kind").GetString() ?? "运动", StartedAt = raw.GetProperty("startedAt").GetDateTimeOffset(), EndedAt = raw.GetProperty("endedAt").GetDateTimeOffset(), Intervals = intervals, SourceRecord = raw.Clone() };
                if (raw.TryGetProperty("activityText", out var shared) && shared.ValueKind == JsonValueKind.String) item.ActivityText = shared.GetString();
                item.Seconds = intervals.Sum(i => Math.Max(0, ((i.End ?? i.Start) - i.Start).TotalSeconds));
                item.HasSteps = intervals.Count > 0 && intervals.All(i => i.Steps != null); item.Steps = intervals.Sum(i => i.Steps ?? 0);
                if (intervals.Count > 0 && intervals.All(i => i.DistanceMeters != null)) item.DistanceOverride = intervals.Sum(i => i.DistanceMeters ?? 0);
                if (raw.TryGetProperty("activity", out var activity) && activity.ValueKind == JsonValueKind.Object) item.Activity = JsonSerializer.Deserialize<ActivityLink>(activity, Wire);
                item.RouteEnabled = raw.TryGetProperty("routeEnabled", out var enabled) && enabled.ValueKind == JsonValueKind.True;
                if (raw.TryGetProperty("route", out var route) && route.ValueKind == JsonValueKind.Array) item.Route = JsonSerializer.Deserialize<List<WorkoutPoint>>(route, Wire) ?? [];
                archive.History.Add(item); archive.Uploaded.Add(item.SyncId); Save();
            }
            string? activityError = null;
            foreach (var item in archive.History.Where(x => x.Activity != null && !archive.ActivityShares.Contains(x.SyncId)).ToArray()) {
                if (!OwnSession(generation)) return;
                try {
                    var linked = item.Activity!;
                    await api.CallAsync($"/api/dear/social/tenants/{linked.TenantID:D}/activities/{linked.Id:D}/moments", HttpMethod.Post,
                        new { text = SharedText(item), requestId = item.SyncId, recordedAt = item.StartedAt });
                    if (!OwnSession(generation)) return;
                    archive.ActivityShares.Add(item.SyncId); Save();
                } catch (Exception error) { if (!OwnSession(generation)) return; activityError = "活动动态待重试：" + error.Message; }
            }
            archive.History = archive.History.OrderByDescending(x => x.StartedAt).ToList(); Save(); Render();
            syncStatus.Text = activityError ?? (archive.History.Any(x => x.Intervals.Count == 0 || x.Intervals[0].Start != x.StartedAt) ? "新记录已同步；旧记录保留本机总时长，并发布到关联活动。" : "运动已同步到当前账号及关联活动。");
        } catch (Exception error) { if (OwnSession(generation)) syncStatus.Text = "同步未完成，本机记录已保留：" + error.Message; }
        finally { syncing = false; Update(); }
    }
    private void StartLocation()
    {
        locationCancellation?.Cancel(); locationCancellation?.Dispose(); locationCancellation = new();
        _ = TrackLocationAsync(locationCancellation.Token);
    }
    private async Task TrackLocationAsync(CancellationToken cancellation)
    {
        try {
            if (await Permissions.RequestAsync<Permissions.LocationWhenInUse>() != PermissionStatus.Granted) { altitudeLabel.Text = "未开启定位，海拔未记录"; return; }
            var workout = archive.Active; var segment = Guid.NewGuid(); Location? previous = null;
            while (!cancellation.IsCancellationRequested && workout != null && archive.Active == workout && workout.RunningSince != null && workout.Route.Count < 20_000) {
                var location = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(GeolocationAccuracy.Best, TimeSpan.FromSeconds(10)), cancellation);
                if (location != null && !cancellation.IsCancellationRequested && archive.Active == workout && workout.RunningSince is { } start && location.Timestamp >= start && Math.Abs((DateTimeOffset.UtcNow - location.Timestamp).TotalSeconds) <= 15 && location.Accuracy is >= 0 and <= 65) {
                    var gap = previous == null ? 0 : (location.Timestamp - previous.Timestamp).TotalSeconds;
                    if (previous == null || gap >= 5 && Location.CalculateDistance(previous, location, DistanceUnits.Kilometers) >= .003) {
                        if (gap > 60) segment = Guid.NewGuid();
                        var (altitude, accuracy) = await SeaLevelAltitude(location);
                        if (cancellation.IsCancellationRequested || archive.Active != workout || workout.RunningSince == null) return;
                        workout.Route.Add(new(location.Latitude, location.Longitude, location.Timestamp, segment, altitude, accuracy)); previous = location;
                        altitudeLabel.Text = altitude is { } value ? $"海拔 {value:F1} 米" : "设备暂未提供海拔"; Save();
                    }
                }
                await Task.Delay(TimeSpan.FromSeconds(5), cancellation);
            }
        } catch (OperationCanceledException) { }
        catch (Exception error) { altitudeLabel.Text = "定位未完成：" + error.Message; }
    }
    private static async Task<(double?, double?)> SeaLevelAltitude(Location location)
    {
        if (location.Altitude is not { } height || !double.IsFinite(height)) return (null, null);
        if (location.AltitudeReferenceSystem == AltitudeReferenceSystem.Geoid) return (height, location.VerticalAccuracy);
        if (!OperatingSystem.IsAndroidVersionAtLeast(34)) return (null, null);
        try {
            return await Task.Run<(double?, double?)>(() => {
                if (!OperatingSystem.IsAndroidVersionAtLeast(34)) return (null, null);
                using var native = new Android.Locations.Location("moment") { Latitude = location.Latitude, Longitude = location.Longitude, Altitude = height };
                if (location.VerticalAccuracy is >= 0 and var accuracy) native.VerticalAccuracyMeters = (float)accuracy;
                using var converter = new Android.Locations.Altitude.AltitudeConverter();
                converter.AddMslAltitudeToLocation(Android.App.Application.Context, native);
                return native.HasMslAltitude ? (native.MslAltitudeMeters, native.HasMslAltitudeAccuracy ? native.MslAltitudeAccuracyMeters : null) : (null, null);
            });
        } catch (Java.IO.IOException) { return (null, null); }
    }
}
