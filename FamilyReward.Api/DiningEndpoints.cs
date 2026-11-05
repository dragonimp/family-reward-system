using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;

// Provider credentials remain on the server. This module stores no users or location history.
internal static class DiningEndpoints
{
    public static void MapDiningEndpoints(this WebApplication app)
    {
        app.MapPost("/api/dining/nearby", async (DiningSearch input, IConfiguration configuration,
            IHttpClientFactory factory, HttpContext context) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            var latitude = input.Latitude; var longitude = input.Longitude;
            if (!double.IsFinite(latitude) || !double.IsFinite(longitude) || Math.Abs(latitude) > 90 || Math.Abs(longitude) > 180)
                return Results.BadRequest(new { error = "定位坐标无效，请重新定位。" });
            var key = configuration["Dining:AmapWebServiceKey"];
            if (string.IsNullOrWhiteSpace(key))
                return Results.Json(new { error = "附近餐厅服务尚未配置，请稍后重试。", code = "dining_provider_not_configured" }, statusCode: 503);
            var client = factory.CreateClient("dining-amap");
            try
            {
                // Device GPS is WGS84; Amap POI and navigation use GCJ-02. Convert through the official API.
                var coordinateUrl = QueryHelpers.AddQueryString("https://restapi.amap.com/v3/assistant/coordinate/convert", new Dictionary<string, string?> {
                    ["key"] = key, ["locations"] = string.Create(CultureInfo.InvariantCulture, $"{longitude:F6},{latitude:F6}"), ["coordsys"] = "gps", ["output"] = "JSON"
                });
                using var conversion = await client.GetAsync(coordinateUrl, context.RequestAborted);
                conversion.EnsureSuccessStatusCode();
                using var coordinates = await JsonDocument.ParseAsync(await conversion.Content.ReadAsStreamAsync(context.RequestAborted), cancellationToken: context.RequestAborted);
                if (Text(coordinates.RootElement, "status") != "1") throw new InvalidDataException();
                var location = Text(coordinates.RootElement, "locations");
                if (!TryCoordinate(location, out _, out _)) throw new InvalidDataException();
                var url = QueryHelpers.AddQueryString("https://restapi.amap.com/v3/place/around", new Dictionary<string, string?> {
                    ["key"] = key, ["location"] = location, ["types"] = "050000", ["radius"] = "3000", ["sortrule"] = "distance", ["offset"] = "25", ["page"] = "1", ["extensions"] = "all", ["output"] = "JSON"
                });
                using var response = await client.GetAsync(url, context.RequestAborted);
                response.EnsureSuccessStatusCode();
                using var data = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(context.RequestAborted), cancellationToken: context.RequestAborted);
                return Results.Ok(new { restaurants = Parse(data.RootElement), attribution = "高德地图", coordinateSystem = "gcj02", distanceKind = "provider" });
            }
            catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { throw; }
            catch (Exception error) when (error is HttpRequestException or JsonException or InvalidDataException or OperationCanceledException)
            { return Results.Json(new { error = "地图服务暂时不可用，请稍后重试。", code = "dining_provider_unavailable" }, statusCode: 502); }
        }).RequireAuthorization().RequireRateLimiting("dining-search");
    }
    internal static List<DiningRestaurant> Parse(JsonElement root)
    {
        if (Text(root, "status") != "1" || !root.TryGetProperty("pois", out var pois) || pois.ValueKind != JsonValueKind.Array) throw new InvalidDataException();
        var restaurants = new List<DiningRestaurant>(); var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var poi in pois.EnumerateArray())
        {
            if (poi.ValueKind != JsonValueKind.Object) continue;
            var id = Text(poi, "id"); var name = Text(poi, "name");
            if (id.Length == 0 || name.Length == 0 || !seen.Add(id) || !TryCoordinate(Text(poi, "location"), out var lat, out var lon)) continue;
            var info = poi.TryGetProperty("biz_ext", out var business) ? business : default;
            var distance = Number(poi, "distance");
            if (distance is null || distance < 0 || distance > 10000) continue;
            var cost = Number(info, "cost"); var rating = Number(info, "rating");
            restaurants.Add(new("amap:" + id, name, Text(poi, "address"), lat, lon, Text(poi, "type"), "amap", cost > 0 ? cost : null, rating is >= 0 and <= 5 ? rating : null, distance.Value));
        }
        return restaurants;
    }
    private static string Text(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() ?? "" : "";
    private static double? Number(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var item) && double.TryParse(item.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var number) && double.IsFinite(number) ? number : null;
    private static bool TryCoordinate(string raw, out double latitude, out double longitude)
    {
        latitude = longitude = 0; var parts = raw.Split(',');
        return parts.Length == 2 && double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out longitude) && double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out latitude) && double.IsFinite(latitude) && double.IsFinite(longitude) && Math.Abs(latitude) <= 90 && Math.Abs(longitude) <= 180;
    }
}
internal sealed record DiningRestaurant(string Id, string Name, string Address, double Latitude, double Longitude, string Category, string Provider, double? Cost, double? Rating, double DistanceMeters);

internal sealed record DiningSearch(double Latitude, double Longitude);
