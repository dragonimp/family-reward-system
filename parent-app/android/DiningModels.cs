using System.Text.Json.Serialization;

namespace LinkoFamily;

public sealed record DiningPlace(string Id, string Name, string Address, double Latitude, double Longitude, string Category, string Provider, double? Cost, double? Rating, double DistanceMeters);
public sealed class DiningHabit
{
    public int Selected { get; set; }
    public int Eaten { get; set; }
    public int Skipped { get; set; }
    public int CheckIns { get; set; }
    [JsonIgnore]
    public int Visits => Selected + CheckIns;
}
public sealed class DiningChoice {
    public Guid Id { get; set; } = Guid.NewGuid();
    public required DiningPlace Place { get; set; }
    public string Mood { get; set; } = "automatic";
    public DateTimeOffset SelectedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? EatenAt { get; set; }
    public bool CheckedIn { get; set; }
    public string? RestaurantType { get; set; }
}
public sealed record DiningCircle(Guid Id, string Name, double Latitude, double Longitude);
public sealed class DiningArchive {
    public List<DiningChoice> History { get; set; } = [];
    public Dictionary<string, DiningHabit> Habits { get; set; } = new(StringComparer.Ordinal);
    public List<DiningPlace> Favorites { get; set; } = [];
    public List<DiningCircle> Circles { get; set; } = [];
    public DiningHabit Habit(string id) { if (!Habits.TryGetValue(id, out var habit)) Habits[id] = habit = new(); return habit; }
    public void CheckIn(DiningPlace place, string? mood, Guid id, string? restaurantType = null, DateTimeOffset? at = null)
    {
        if (History.Any(c => c.Id == id)) return;
        History.Insert(0, new()
        {
            Id = id, Place = place, Mood = mood ?? "automatic", SelectedAt = at?.ToUniversalTime() ?? DateTimeOffset.UtcNow,
            CheckedIn = true, RestaurantType = string.IsNullOrWhiteSpace(restaurantType) ? null : restaurantType.Trim()
        });
        if (History.Count > 300) History.RemoveRange(300, History.Count - 300);
        var habit = Habit(place.Id);
        habit.CheckIns++;
    }
    public void ConfirmEaten(Guid id) {
        var choice = History.FirstOrDefault(c => c.Id == id);
        if (choice is null || choice.CheckedIn || choice.EatenAt is not null) return;
        choice.EatenAt = DateTimeOffset.UtcNow; Habit(choice.Place.Id).Eaten++;
    }
}
public static class DiningRecommendation {
    public static double Weight(DiningPlace place, string mood, DiningArchive archive) {
        var habit = archive.Habits.GetValueOrDefault(place.Id) ?? new();
        var value = 1 / (1 + Math.Max(0, place.DistanceMeters) / 1500);
        value *= 1 + Math.Min(4, Math.Log(1 + habit.Visits + habit.Eaten * 2));
        if (archive.Favorites.Any(p => p.Id == place.Id)) value *= 2;
        value /= 1 + Math.Min(habit.Skipped, 5) * 0.12;
        if (place.Rating is >= 0 and <= 5) value *= 0.7 + place.Rating.Value / 5;
        if (mood == "familiar") value *= habit.Visits > 0 ? 4 : 1;
        else if (mood == "fresh") value *= habit.Visits == 0 ? 5 : 0.8;
        else if (mood == "budget") value *= place.Cost is > 0 ? Math.Clamp(40 / place.Cost.Value, 0.25, 4) : 1 / (1 + Math.Max(0, place.DistanceMeters) / 500);
        else if (mood == "treat") value *= place.Cost is > 0 ? Math.Clamp(place.Cost.Value / 40, 0.5, 3) : archive.Favorites.Any(p => p.Id == place.Id) || habit.Eaten > 0 ? 2 : 1;
        else if (mood == "spicy" && new[] { "川", "湘", "辣", "火锅", "chili", "sichuan", "hunan" }.Any(k => (place.Name + place.Category).Contains(k, StringComparison.OrdinalIgnoreCase))) value *= 4;
        return Math.Max(0.01, value);
    }
    public static DiningPlace? Pick(IEnumerable<DiningPlace> places, string mood, DiningArchive archive, string? excluding, double? draw = null) {
        var unique = places.Where(p => !string.IsNullOrWhiteSpace(p.Name) && double.IsFinite(p.Latitude) && double.IsFinite(p.Longitude) && Math.Abs(p.Latitude) <= 90 && Math.Abs(p.Longitude) <= 180).DistinctBy(p => p.Id).ToList();
        var alternatives = unique.Where(p => p.Id != excluding).ToList();
        var candidates = alternatives.Count > 0 ? alternatives : unique;
        var weights = candidates.Select(p => Weight(p, mood, archive)).ToList();
        var target = Math.Clamp(draw ?? Random.Shared.NextDouble(), 0, 0.999999) * weights.Sum();
        for (var i = 0; i < candidates.Count; i++) { target -= weights[i]; if (target < 0) return candidates[i]; }
        return candidates.LastOrDefault();
    }
}

public static class DiningAccount { public static string Identity(string raw) => Guid.TryParseExact(raw, "D", out var id) ? id.ToString("D") : raw; }
