namespace LinkoFamily;
public sealed record ExerciseRouteCoordinate(double Latitude, double Longitude, DateTimeOffset RecordedAt, Guid Segment);
public static class ExerciseRouteGeometry
{
    public static List<List<double[]>> Segments(IEnumerable<ExerciseRouteCoordinate> points)
    {
        List<List<double[]>> result = []; ExerciseRouteCoordinate? previous = null;
        foreach (var point in points) {
            if (!double.IsFinite(point.Latitude) || !double.IsFinite(point.Longitude) || Math.Abs(point.Latitude)>90 || Math.Abs(point.Longitude)>180) { previous = null; continue; }
            if (previous == null || previous.Segment != point.Segment || point.RecordedAt <= previous.RecordedAt || (point.RecordedAt-previous.RecordedAt).TotalSeconds>60) result.Add([]);
            result[^1].Add([point.Latitude, point.Longitude]); previous = point;
        }
        return result;
    }
}

public static class ExercisePresentation
{
    public static string Clock(double duration)
    {
        var seconds = double.IsFinite(duration) ? (long)Math.Max(0, duration) : 0;
        return $"{seconds / 3600:00}:{seconds / 60 % 60:00}:{seconds % 60:00}";
    }
}
