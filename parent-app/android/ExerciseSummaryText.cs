using System.Globalization;
namespace LinkoFamily;
public static class ExerciseSummaryText
{
    public static string Format(string kind, double durationSeconds, double? distanceMeters, int? steps, IEnumerable<double> altitudeMeters)
    {
        var seconds = (long)Math.Max(0, durationSeconds);
        var lines = new List<string> { $"{kind} · {seconds / 3600:00}:{seconds / 60 % 60:00}:{seconds % 60:00}" };
        lines.Add(distanceMeters is { } distance ? (distance / 1000).ToString("F2", CultureInfo.InvariantCulture) + " 公里" : "距离未获取");
        if (steps is { } count) lines.Add(count.ToString(CultureInfo.InvariantCulture) + " 步");
        var heights = altitudeMeters.ToList();
        if (heights.Count > 0) lines.Add("海拔 " + heights.Min().ToString("F1", CultureInfo.InvariantCulture) + "–" + heights.Max().ToString("F1", CultureInfo.InvariantCulture) + " 米");
        return string.Join("\n", lines);
    }
}
