using LinkoFamily;
using System.Globalization;
var destination = new MapDestination("厦门餐厅 & 茶馆", 24.48, 118.08, MapCoordinateSystem.Gcj02);
CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("fr-FR");
foreach (var mode in Enum.GetValues<NavigationMode>())
{
    var amap = ExternalMapRoutes.Build(MapApp.Amap, destination, mode).OriginalString;
    var tencent = ExternalMapRoutes.Build(MapApp.Tencent, destination, mode, "test-ref").OriginalString;
    var amapMode = mode switch { NavigationMode.Driving => "0", NavigationMode.Walking => "2", NavigationMode.Transit => "1", NavigationMode.Cycling => "3", _ => throw new Exception() };
    var tencentMode = mode.ToString() switch { "Driving" => "drive", "Walking" => "walk", "Transit" => "bus", "Cycling" => "bike", _ => throw new Exception() };
    if (!amap.EndsWith("&t=" + amapMode) || !tencent.Contains("?type=" + tencentMode + "&")) throw new Exception("Incorrect travel mode");
    if (!amap.Contains("dlat=24.48&dlon=118.08") || !tencent.Contains("tocoord=24.48,118.08") || !Uri.UnescapeDataString(amap).Contains(destination.Name)) throw new Exception("Coordinate order or encoding regression");
}
foreach (var invalid in new[] { destination with { Latitude = double.NaN }, destination with { Longitude = 181 }, destination with { Name = " " }, destination with { CoordinateSystem = (MapCoordinateSystem)99 } })
{
    try { ExternalMapRoutes.Build(MapApp.Amap, invalid, NavigationMode.Walking); throw new Exception("Invalid destination accepted"); }
    catch (ArgumentException) { }
}
try { ExternalMapRoutes.Build(MapApp.Tencent, destination, NavigationMode.Walking); throw new Exception("Missing referer accepted"); }
catch (InvalidOperationException) { }
Console.WriteLine("PASS four modes for both providers, Chinese encoding, invariant coordinates, invalid inputs and missing referer");
