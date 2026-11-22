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
        app.MapMethods("/api/exercise/share-invitations/{code:guid}", ["GET", "HEAD"], (Guid code, HttpResponse response) =>
        {
            response.Headers.CacheControl = "no-store";
            response.Headers["Referrer-Policy"] = "no-referrer";
            response.Headers["X-Robots-Tag"] = "noindex, nofollow";
            response.Headers.XContentTypeOptions = "nosniff";
            return code == Guid.Empty ? Results.NotFound() : Results.Content(InvitationPage(code), "text/html; charset=utf-8");
        }).AllowAnonymous();

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

    private static string InvitationPage(Guid code)
    {
        const string origin = "https://happylife.ai.impx.net";
        const string icon = origin + "/api/dear/public/brand/icon.png";
        const string title = "Linko Moment · 好友运动邀请";
        const string description = "打开 Linko Moment，查看好友运动或加入并记录自己的轨迹。";
        var appLink = $"linkomoment://workout?code={code:D}";
        var page = $"{origin}/api/exercise/share-invitations/{code:D}";
        return $$"""
            <!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <title>{{title}}</title><meta name="description" content="{{description}}">
            <meta property="og:type" content="website"><meta property="og:title" content="{{title}}">
            <meta property="og:description" content="{{description}}"><meta property="og:image" content="{{icon}}">
            <meta property="og:url" content="{{page}}">
            <meta name="apple-itunes-app" content="app-id=6828813434, app-argument={{appLink}}">
            <style>
            :root{color-scheme:light dark;font-family:system-ui,sans-serif}body{margin:0;padding:40px 16px;background:#eaf4ef;color:#15382e}
            main{box-sizing:border-box;max-width:470px;margin:auto;padding:30px;background:#fff;border-radius:24px}
            img{border-radius:12px}h1{font-size:26px;margin:16px 0 8px}p,label{font-size:15px;line-height:1.6}
            a{display:block;text-align:center;padding:12px;border-radius:12px;margin-top:10px;color:#195743}a.primary{background:#146755;color:white;text-decoration:none;font-weight:600}
            input{box-sizing:border-box;width:100%;padding:10px;font:15px system-ui;border:1px solid #819b92;border-radius:8px}
            @media(prefers-color-scheme:dark){body{background:#101d19;color:#e5f4ee}main{background:#182e26}a{color:#9adbc4} }
            </style></head><body><main><img src="{{icon}}" width="48" height="48" alt="Linko Moment">
            <h1>好友运动邀请</h1><p>{{description}}</p>
            <a class="primary" href="{{appLink}}">在 App 中打开</a>
            <p>如果微信无法打开 App，请点右上角「···」，选择在系统浏览器中打开。</p>
            <label for="code">也可以复制邀请码，在 App 的「运动 → 好友运动」里打开。</label>
            <input id="code" readonly value="{{code:D}}">
            <a href="https://home.ai.impx.net/invite/SW2wL0kd3pX20t6xSNLXsDK4" rel="noreferrer">安装测试版</a>
            <a href="https://apps.apple.com/app/id6828813434" rel="noreferrer">App Store 正式版</a>
            </main></body></html>
            """;
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
