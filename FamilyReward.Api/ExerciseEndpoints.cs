using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;

internal static class ExerciseEndpoints
{
    internal sealed record Interval(DateTimeOffset Start, DateTimeOffset? End, int? Steps, double? DistanceMeters);
    internal sealed record Point(double Latitude, double Longitude, DateTimeOffset RecordedAt, Guid Segment,
        [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] double? AltitudeMeters = null,
        [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] double? VerticalAccuracyMeters = null);
    internal sealed record Activity(Guid TenantID, Guid Id, string Title);
    internal sealed record Record(Guid Id, string Kind, DateTimeOffset StartedAt, DateTimeOffset? EndedAt,
        Interval[] Intervals, bool? RouteEnabled, Point[]? Route,
        [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] Activity? Activity = null,
        [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] string? ActivityText = null);
    internal static bool Valid(Record r)
    {
        if (r.Id == Guid.Empty || string.IsNullOrWhiteSpace(r.Kind) || r.Kind.Length > 40 || r.EndedAt is not { } end ||
            end < r.StartedAt || end > DateTimeOffset.UtcNow.AddMinutes(5) || r.Intervals is not { Length: > 0 and <= 1000 } ||
            r.Intervals[0].Start != r.StartedAt || r.Route?.Length > 20_000) return false;
        if (r.Activity is { } activity && (activity.TenantID == Guid.Empty || activity.Id == Guid.Empty ||
            activity.Title is null || activity.Title.Length > 300)) return false;
        if (r.ActivityText is { } text && (string.IsNullOrWhiteSpace(text) || text.Length > 1000)) return false;
        var previous = r.StartedAt;
        foreach (var interval in r.Intervals) {
            if (interval == null || interval.End is not { } stop || stop < interval.Start || interval.Start < previous || stop > end ||
                interval.Steps < 0 || interval.DistanceMeters is { } distance && (!double.IsFinite(distance) || distance < 0)) return false;
            previous = stop;
        }
        DateTimeOffset? last = null;
        foreach (var point in r.Route ?? []) {
            if (point == null || point.Segment == Guid.Empty || !double.IsFinite(point.Latitude) || !double.IsFinite(point.Longitude) ||
                point.AltitudeMeters is { } altitude && !double.IsFinite(altitude) ||
                point.VerticalAccuracyMeters is { } accuracy && (!double.IsFinite(accuracy) || accuracy < 0) ||
                Math.Abs(point.Latitude) > 90 || Math.Abs(point.Longitude) > 180 || point.RecordedAt < r.StartedAt || point.RecordedAt > end ||
                last is { } before && point.RecordedAt <= before || !r.Intervals.Any(i => point.RecordedAt >= i.Start && point.RecordedAt <= i.End)) return false;
            last = point.RecordedAt;
        }
        return true;
    }

    public static void MapExerciseEndpoints(this WebApplication app)
    {
        // This is normal user content storage, outside versioned releases. No startup data migration or seeding.
        var root = app.Configuration["Exercise:DataDirectory"] ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LinkoMoment", "exercise-records");
        var store = new ExerciseRecordStore(Path.GetFullPath(root));
        var group = app.MapGroup("/api/exercise/records").RequireAuthorization();
        static string? Owner(ClaimsPrincipal user) {
            var subject = user.FindFirstValue("sub") ?? user.FindFirstValue(ClaimTypes.NameIdentifier);
            return string.IsNullOrWhiteSpace(subject) ? null : Guid.TryParse(subject, out var id) ? id.ToString("D") : subject;
        }
        group.MapGet("", (Guid? after, ClaimsPrincipal user, HttpResponse response) => {
            response.Headers.CacheControl = "private, no-store";
            var owner = Owner(user); return owner == null ? Results.Unauthorized() : Results.Ok(store.List(owner, after));
        });
        group.MapGet("/{id:guid}", (Guid id, ClaimsPrincipal user, HttpResponse response) => {
            response.Headers.CacheControl = "private, no-store";
            var owner = Owner(user); if (owner == null) return Results.Unauthorized();
            var data = store.Read(owner, id); return data == null ? Results.NotFound() : Results.Bytes(data, "application/json");
        });
        group.MapPut("/{id:guid}", async (Guid id, Record record, ClaimsPrincipal user, CancellationToken ct) => {
            var owner = Owner(user); if (owner == null) return Results.Unauthorized();
            if (id != record.Id || !Valid(record)) return Results.BadRequest(new { error = "运动记录或轨迹无效，请保留本机记录后重试。" });
            return await store.Put(owner, record, ct) ? Results.Ok(new { id, saved = true }) : Results.Conflict(new { error = "这条运动记录已删除，或已存在不同内容。" });
        }).WithMetadata(new RequestSizeLimitAttribute(5 * 1024 * 1024));
        group.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, CancellationToken ct) => {
            var owner = Owner(user); if (owner == null) return Results.Unauthorized();
            await store.Delete(owner, id, ct); return Results.Ok(new { id, deleted = true });
        });
    }
}

internal sealed class ExerciseRecordStore(string root)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private string Folder(string owner) => Path.Combine(root, Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(owner))));
    private static string Key(Guid id) => id.ToString("N");
    private static void PrivateDirectory(string path) {
        Directory.CreateDirectory(path);
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }
    private async Task<FileStream> Lock(string folder, CancellationToken ct) {
        PrivateDirectory(folder);
        while (true) {
            ct.ThrowIfCancellationRequested();
            try { return new FileStream(Path.Combine(folder, ".lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) { await Task.Delay(100, ct); }
        }
    }
    public object List(string owner, Guid? after) {
        var folder = Folder(owner);
        var keys = Directory.Exists(folder) ? Directory.EnumerateFiles(folder).Select(Path.GetFileName)
            .Where(n => n != null && (n.EndsWith(".json") || n.EndsWith(".deleted")))
            .Select(n => Path.GetFileNameWithoutExtension(n)!).Where(n => Guid.TryParseExact(n, "N", out _)).Distinct()
            .Where(n => after == null || string.CompareOrdinal(n, Key(after.Value)) > 0).Order(StringComparer.Ordinal).Take(101).ToArray() : [];
        return new { records = keys.Take(100).Select(k => new { id = Guid.ParseExact(k, "N"), deleted = File.Exists(Path.Combine(folder, k + ".deleted")) }),
            next = keys.Length > 100 ? (Guid?)Guid.ParseExact(keys[99], "N") : null };
    }
    public byte[]? Read(string owner, Guid id) {
        var folder = Folder(owner); var file = Path.Combine(folder, Key(id) + ".json");
        if (File.Exists(Path.Combine(folder, Key(id) + ".deleted"))) return null;
        try { var bytes = File.ReadAllBytes(file); return File.Exists(Path.Combine(folder, Key(id) + ".deleted")) ? null : bytes; }
        catch (FileNotFoundException) { return null; } catch (DirectoryNotFoundException) { return null; }
    }
    private static bool SameMeasurement(ExerciseEndpoints.Record left, ExerciseEndpoints.Record right) =>
        left.Id == right.Id && left.Kind == right.Kind && left.StartedAt == right.StartedAt && left.EndedAt == right.EndedAt &&
        left.Intervals.SequenceEqual(right.Intervals) && (left.RouteEnabled ?? false) == (right.RouteEnabled ?? false) &&
        (left.Route ?? []).SequenceEqual(right.Route ?? []) && left.Activity == right.Activity;

    public async Task<bool> Put(string owner, ExerciseEndpoints.Record record, CancellationToken ct) {
        var folder = Folder(owner); await using var held = await Lock(folder, ct);
        if (File.Exists(Path.Combine(folder, Key(record.Id) + ".deleted"))) return false;
        var bytes = JsonSerializer.SerializeToUtf8Bytes(record, Json); var file = Path.Combine(folder, Key(record.Id) + ".json");
        var replacing = File.Exists(file);
        if (replacing) {
            var existingBytes = await File.ReadAllBytesAsync(file, ct);
            if (bytes.SequenceEqual(existingBytes)) return true;
            ExerciseEndpoints.Record? existing;
            try { existing = JsonSerializer.Deserialize<ExerciseEndpoints.Record>(existingBytes, Json); }
            catch (JsonException) { return false; }
            if (existing is null || !SameMeasurement(existing, record)) return false;
            // An optional derived summary may arrive later through phone/Watch delivery.
            // Keep the first non-empty snapshot and never overwrite measured data.
            if (record.ActivityText is null || record.ActivityText == existing.ActivityText) return true;
            if (existing.ActivityText is not null) return false;
            bytes = JsonSerializer.SerializeToUtf8Bytes(existing with { ActivityText = record.ActivityText }, Json);
        }
        var temp = Path.Combine(folder, Guid.NewGuid().ToString("N") + ".tmp");
        try {
            await File.WriteAllBytesAsync(temp, bytes, ct);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(temp, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            File.Move(temp, file, overwrite: replacing); return true;
        } finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public async Task Delete(string owner, Guid id, CancellationToken ct) {
        var folder = Folder(owner); await using var held = await Lock(folder, ct);
        // Durable tombstones prevent an offline device from resurrecting a deleted record.
        var tombstone = Path.Combine(folder, Key(id) + ".deleted");
        if (!File.Exists(tombstone)) await File.WriteAllBytesAsync(tombstone, [], ct);
        var file = Path.Combine(folder, Key(id) + ".json"); if (File.Exists(file)) File.Delete(file);
    }
}
