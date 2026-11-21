using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;

internal static class ExerciseShareEndpoints
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private sealed record Context(string Name, Guid WorkoutId);
    private sealed record Route(Guid WorkoutId, ExerciseEndpoints.Point[] Points);
    private sealed record Track(int Id, string Name, Guid WorkoutId, ExerciseEndpoints.Point[] Points);
    private sealed record Share(string Kind, DateTimeOffset ExpiresAt, Dictionary<string, Track> Members);
    private sealed record Create(string Kind, string Name, Guid WorkoutId);

    public static void MapExerciseShares(this WebApplication app, string exerciseRoot)
    {
        var root = Path.Combine(exerciseRoot, "shares");
        var routes = app.MapGroup("/api/exercise/shares").RequireAuthorization();
        routes.MapPost("", async (Create input, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (Subject(user) is not { } subject) return Results.Unauthorized();
            if (!ValidName(input.Name) || string.IsNullOrWhiteSpace(input.Kind) || input.Kind.Length > 40 || input.WorkoutId == Guid.Empty)
                return Results.BadRequest();
            var code = Guid.NewGuid();
            var share = new Share(input.Kind, DateTimeOffset.UtcNow.AddDays(7),
                new() { [subject] = new Track(0, input.Name, input.WorkoutId, []) });
            Directory.CreateDirectory(root);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(root, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            await Save(root, code, share, ct);
            return Results.Ok(new { code });
        });

        routes.MapGet("/{code:guid}", async (Guid code, ClaimsPrincipal user, HttpResponse response, CancellationToken ct) =>
        {
            if (Subject(user) is not { } subject) return Results.Unauthorized();
            response.Headers.CacheControl = "private, no-store";
            var share = await Read(root, code, ct);
            return share == null ? Results.NotFound() : Results.Ok(new
            {
                share.Kind, share.ExpiresAt,
                isOwner = share.Members.GetValueOrDefault(subject)?.Id == 0,
                workoutId = share.Members.GetValueOrDefault(subject)?.WorkoutId,
                tracks = share.Members.Values.Select(x => new { x.Id, x.Name, x.Points })
            });
        });

        routes.MapPut("/{code:guid}/member", (Guid code, Context input, ClaimsPrincipal user, CancellationToken ct) =>
            Edit(root, code, Subject(user), (share, subject) =>
            {
                if (!ValidName(input.Name) || input.WorkoutId == Guid.Empty) return Results.BadRequest();
                if (share.Members.TryGetValue(subject, out var existing))
                    return Results.Ok(new { workoutId = existing.WorkoutId });
                if (share.Members.Count >= 12) return Results.Conflict();
                share.Members[subject] = new Track(Enumerable.Range(1, 11).First(id => share.Members.Values.All(track => track.Id != id)), input.Name, input.WorkoutId, []);
                return Results.Ok(new { workoutId = input.WorkoutId });
            }, ct));

        routes.MapPut("/{code:guid}/track", (Guid code, Route input, ClaimsPrincipal user, CancellationToken ct) =>
            Edit(root, code, Subject(user), (share, subject) =>
            {
                if (!share.Members.TryGetValue(subject, out var member) || member.WorkoutId != input.WorkoutId)
                    return Results.Forbid();
                if (input.Points is not { Length: > 0 and <= 2000 }) return Results.BadRequest();
                var previous = DateTimeOffset.MinValue;
                foreach (var point in input.Points)
                {
                    if (point == null || point.Segment == Guid.Empty || !double.IsFinite(point.Latitude) || !double.IsFinite(point.Longitude) ||
                        Math.Abs(point.Latitude) > 90 || Math.Abs(point.Longitude) > 180 || point.RecordedAt <= previous ||
                        point.RecordedAt > DateTimeOffset.UtcNow.AddMinutes(5)) return Results.BadRequest();
                    previous = point.RecordedAt;
                }
                if (member.Points.LastOrDefault()?.RecordedAt > previous) return Results.Conflict();
                share.Members[subject] = member with { Points = input.Points };
                return Results.Ok();
            }, ct)).WithMetadata(new RequestSizeLimitAttribute(750_000));

        routes.MapDelete("/{code:guid}/member", (Guid code, ClaimsPrincipal user, CancellationToken ct) =>
            Edit(root, code, Subject(user), (share, subject) =>
            {
                if (share.Members.GetValueOrDefault(subject)?.Id == 0) return Results.Forbid();
                share.Members.Remove(subject);
                return Results.Ok();
            }, ct));

        routes.MapDelete("/{code:guid}", async (Guid code, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (Subject(user) is not { } subject) return Results.Unauthorized();
            if (!File.Exists(FilePath(root, code))) return Results.NotFound();
            await using var held = await Lock(root, ct);
            var share = await Read(root, code, ct);
            if (share == null) return Results.NotFound();
            if (share.Members.GetValueOrDefault(subject)?.Id != 0) return Results.Forbid();
            File.Delete(FilePath(root, code));
            return Results.NoContent();
        });
    }

    private static bool ValidName(string? value) => !string.IsNullOrWhiteSpace(value) && value.Length <= 100;

    private static string? Subject(ClaimsPrincipal user)
    {
        var subject = user.FindFirstValue("sub") ?? user.FindFirstValue(ClaimTypes.NameIdentifier);
        return string.IsNullOrWhiteSpace(subject) ? null : Guid.TryParse(subject, out var id) ? id.ToString("D") : subject;
    }

    private static string FilePath(string root, Guid code) => Path.Combine(root, code.ToString("N") + ".json");

    private static async Task<Share?> Read(string root, Guid code, CancellationToken ct)
    {
        try
        {
            var share = JsonSerializer.Deserialize<Share>(await File.ReadAllBytesAsync(FilePath(root, code), ct), Json);
            return share?.ExpiresAt > DateTimeOffset.UtcNow ? share : null;
        }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
    }

    private static async Task Save(string root, Guid code, Share share, CancellationToken ct)
    {
        var target = FilePath(root, code);
        var temp = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await File.WriteAllBytesAsync(temp, JsonSerializer.SerializeToUtf8Bytes(share, Json), ct);
            File.Move(temp, target, overwrite: true);
        }
        finally { File.Delete(temp); }
    }

    private static async Task<FileStream> Lock(string root, CancellationToken ct)
    {
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            try { return new FileStream(Path.Combine(root, ".lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) { await Task.Delay(80, ct); }
        }
    }

    private static async Task<IResult> Edit(string root, Guid code, string? subject,
        Func<Share, string, IResult> edit, CancellationToken ct)
    {
        if (subject == null) return Results.Unauthorized();
        if (!File.Exists(FilePath(root, code))) return Results.NotFound();
        await using var held = await Lock(root, ct);
        var share = await Read(root, code, ct);
        if (share == null) return Results.NotFound();
        var result = edit(share, subject);
        if (result is IStatusCodeHttpResult { StatusCode: 200 }) await Save(root, code, share, ct);
        return result;
    }
}
