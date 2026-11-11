using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;

internal sealed record HikingSearch(double Latitude, double Longitude, bool Scenic = false);
internal static class HikingEndpoints
{
    public static void MapHikingEndpoints(this WebApplication app)
    {
        app.MapPost("/api/hiking/nearby", async (HikingSearch input, IConfiguration configuration,
            IHttpClientFactory factory, HttpContext context) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            var latitude = input.Latitude; var longitude = input.Longitude;
            if (!double.IsFinite(latitude) || !double.IsFinite(longitude) || Math.Abs(latitude) > 90 || Math.Abs(longitude) > 180)
                return Results.BadRequest(new { error = "定位坐标无效，请重新定位。" });
            var key = configuration["Dining:AmapWebServiceKey"];
            if (string.IsNullOrWhiteSpace(key))
                return Results.Json(new { error = "附近山峰服务尚未配置，请稍后重试。", code = "hiking_provider_not_configured" }, statusCode: 503);
            var client = factory.CreateClient("dining-amap");
            try
            {
                // Device GPS is WGS84; Amap POI and navigation use GCJ-02. Convert through the official API.
                var location = string.Create(CultureInfo.InvariantCulture, $"{longitude:F6},{latitude:F6}");
                if (!input.Scenic)
                {
                var coordinateUrl = QueryHelpers.AddQueryString("https://restapi.amap.com/v3/assistant/coordinate/convert", new Dictionary<string, string?> {
                    ["key"] = key, ["locations"] = string.Create(CultureInfo.InvariantCulture, $"{longitude:F6},{latitude:F6}"), ["coordsys"] = "gps", ["output"] = "JSON"
                });
                using var conversion = await client.GetAsync(coordinateUrl, context.RequestAborted);
                conversion.EnsureSuccessStatusCode();
                using var coordinates = await JsonDocument.ParseAsync(await conversion.Content.ReadAsStreamAsync(context.RequestAborted), cancellationToken: context.RequestAborted);
                if (coordinates.RootElement.GetProperty("status").GetString() != "1") throw new InvalidDataException();
                location = coordinates.RootElement.GetProperty("locations").GetString() ?? "";
                }
                if (!DiningEndpoints.TryCoordinate(location, out var centerLatitude, out var centerLongitude)) throw new InvalidDataException();
                var url = QueryHelpers.AddQueryString("https://restapi.amap.com/v3/place/around", new Dictionary<string, string?> {
                    ["key"] = key, ["location"] = location, ["types"] = "110000", ["keywords"] = input.Scenic ? "" : "山", ["radius"] = input.Scenic ? "5000" : "30000", ["sortrule"] = "distance", ["offset"] = "25", ["page"] = "1", ["extensions"] = "all", ["output"] = "JSON"
                });
                using var response = await client.GetAsync(url, context.RequestAborted);
                response.EnsureSuccessStatusCode();
                using var data = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(context.RequestAborted), cancellationToken: context.RequestAborted);
                return Results.Ok(new { places = DiningEndpoints.Parse(data.RootElement).Select(p => new { p.Id, p.Name, p.Address, p.Latitude, p.Longitude, p.DistanceMeters, elevationMeters = (double?)null, trailSurface = (string?)null, hikingDurationMinutes = (int?)null, accessStatus = "unverified" }), attribution = "高德地图", coordinateSystem = "gcj02", distanceKind = "provider", searchCenter = new { latitude = centerLatitude, longitude = centerLongitude } });
            }
            catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { throw; }
            catch (Exception error) when (error is HttpRequestException or JsonException or InvalidDataException or OperationCanceledException)
            { return Results.Json(new { error = "地图服务暂时不可用，请稍后重试。", code = "hiking_provider_unavailable" }, statusCode: 502); }
        }).RequireAuthorization().RequireRateLimiting("dining-search");
    }
}
