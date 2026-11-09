using System.Globalization;

namespace LinkoFamily;

public enum MapApp { Amap, Tencent }
public enum NavigationMode { Driving, Walking, Transit, Cycling }
public enum MapCoordinateSystem { Gcj02 }
public sealed record MapDestination(string Name, double Latitude, double Longitude, MapCoordinateSystem CoordinateSystem);

public interface IExternalMapNavigator
{
    IReadOnlyList<MapApp> GetAvailableMaps();
    void OpenNavigation(MapApp app, MapDestination destination, NavigationMode mode);
}

public static class ExternalMapRoutes
{
    public static string Package(MapApp app) => app switch
    {
        MapApp.Amap => "com.autonavi.minimap",
        MapApp.Tencent => "com.tencent.map",
        _ => throw new ArgumentOutOfRangeException(nameof(app))
    };

    public static Uri Build(MapApp app, MapDestination destination, NavigationMode mode, string? referer = null)
    {
        if (destination.CoordinateSystem != MapCoordinateSystem.Gcj02 || string.IsNullOrWhiteSpace(destination.Name)
            || !double.IsFinite(destination.Latitude) || !double.IsFinite(destination.Longitude)
            || Math.Abs(destination.Latitude) > 90 || Math.Abs(destination.Longitude) > 180)
            throw new ArgumentException("目的地名称或 GCJ-02 坐标无效。");
        var lat = destination.Latitude.ToString("R", CultureInfo.InvariantCulture);
        var lon = destination.Longitude.ToString("R", CultureInfo.InvariantCulture);
        var name = Uri.EscapeDataString(destination.Name);
        if (app == MapApp.Amap)
        {
            var type = mode switch { NavigationMode.Driving => "0", NavigationMode.Transit => "1", NavigationMode.Walking => "2", NavigationMode.Cycling => "3", _ => throw new ArgumentOutOfRangeException(nameof(mode)) };
            return new Uri($"amapuri://route/plan/?sourceApplication=Linko%20Moment&dlat={lat}&dlon={lon}&dname={name}&dev=0&t={type}");
        }
        if (app != MapApp.Tencent) throw new ArgumentOutOfRangeException(nameof(app));
        if (string.IsNullOrWhiteSpace(referer)) throw new InvalidOperationException("腾讯地图导航尚未配置应用 referer，请先选择高德地图。");
        var travel = mode switch { NavigationMode.Driving => "drive", NavigationMode.Walking => "walk", NavigationMode.Transit => "bus", NavigationMode.Cycling => "bike", _ => throw new ArgumentOutOfRangeException(nameof(mode)) };
        return new Uri($"qqmap://map/routeplan?type={travel}&to={name}&tocoord={lat},{lon}&referer={Uri.EscapeDataString(referer)}");
    }
}
