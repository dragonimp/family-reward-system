using System.Globalization;
using System.Text.Json;
using System.Xml;
using System.Xml.Linq;

namespace LinkoFamily;

internal sealed class HikingPage : ContentPage
{
    readonly FamilyStore api;
    readonly VerticalStackLayout rows = new() { Padding = 20, Spacing = 14 };
    readonly VerticalStackLayout results = new() { Spacing = 12 };
    readonly Label status = new();
    bool busy;
    public HikingPage(FamilyStore api)
    {
        this.api = api; Title = "爬山";
        rows.Add(MomentStyle.Title("附近山峰与路线", 26));
        rows.Add(new Label { Text = "地点搜索不代表开放或允许攀登。海拔、路面和登顶时长以景区及路线资料为准。" });
        rows.Add(MomentStyle.Action("定位搜索附近的山（30公里）", () => _ = Search()));
        rows.Add(MomentStyle.Action("导入 GPX 路线", () => _ = Import()));
        rows.Add(status); rows.Add(results); Content = new ScrollView { Content = rows };
    }
    async Task Search(double? lat = null, double? lon = null)
    {
        if (busy) return;
        busy = true; status.Text = "正在查询…";
        try {
            if (lat == null) {
                var location = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(GeolocationAccuracy.Medium, TimeSpan.FromSeconds(15)));
                if (location == null) throw new InvalidOperationException("未获取位置，请检查定位权限。");
                lat = location.Latitude; lon = location.Longitude;
            }
            var data = await api.CallAsync("/api/hiking/nearby", HttpMethod.Post, new { latitude = lat, longitude = lon, scenic = lat != null && scenicSearch });
            results.Clear();
            foreach (var place in data.GetProperty("places").EnumerateArray()) {
                var name = place.GetProperty("name").GetString() ?? "地点";
                var latitude = place.GetProperty("latitude").GetDouble(); var longitude = place.GetProperty("longitude").GetDouble();
                results.Add(MomentStyle.Title(name, 21));
                results.Add(new Label { Text = place.GetProperty("address").GetString() + $"\n直线距离约 {place.GetProperty("distanceMeters").GetDouble() / 1000:F1} 公里\n海拔：未核实 · 台阶/山路：未核实 · 登山时长：未核实\n开放及登山许可：请向景区核实" });
                results.Add(MomentStyle.Action("高德查看位置并导航", async () => {
                    try { new ExternalMapNavigator(ExternalMapNavigator.ConfiguredTencentReferer).OpenNavigation(MapApp.Amap, new MapDestination(name, latitude, longitude, MapCoordinateSystem.Gcj02), NavigationMode.Driving); }
                    catch { await DisplayAlertAsync("地图无法打开", "请安装或启用高德地图后重试。", "知道了"); }
                }));
                if (!scenicSearch) results.Add(MomentStyle.Action("查看周边景点（5公里）", () => { scenicSearch = true; _ = Search(latitude, longitude); }));
            }
            status.Text = results.Count == 0 ? "附近暂未找到结果。" : "地点来源：高德地图 · 搜索结果并非登山路线推荐";
        } catch { status.Text = "未能查询地点，请检查定位权限、网络或地图服务配置后重试。"; }
        finally { busy = false; scenicSearch = false; }
    }
    bool scenicSearch;
    async Task Import()
    {
        if (busy) return;
        busy = true;
        try {
            var file = await FilePicker.Default.PickAsync(new PickOptions { PickerTitle = "选择 GPX 登山路线" });
            if (file == null) return;
            if (!file.FileName.EndsWith(".gpx", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
            await using var stream = await file.OpenReadAsync();
            using var reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 5_000_000, Async = true });
            var xml = await XDocument.LoadAsync(reader, LoadOptions.None, CancellationToken.None);
            if (xml.Root?.Name.LocalName != "gpx") throw new InvalidDataException();
            var points = new List<ExercisePanel.WorkoutPoint>();
            var segments = xml.Descendants().Where(e => e.Name.LocalName is "trkseg" or "rte");
            foreach (var segment in segments) {
                var id = Guid.NewGuid();
                foreach (var p in segment.Elements().Where(e => e.Name.LocalName is "trkpt" or "rtept")) {
                    double Number(string? value) => double.Parse(value ?? "", CultureInfo.InvariantCulture);
                    var lat = Number(p.Attribute("lat")?.Value); var lon = Number(p.Attribute("lon")?.Value);
                    if (!double.IsFinite(lat) || !double.IsFinite(lon) || Math.Abs(lat) > 90 || Math.Abs(lon) > 180 || points.Count >= 20000) throw new InvalidDataException();
                    double? altitude = null;
                    if (p.Elements().FirstOrDefault(e => e.Name.LocalName == "ele") is { } ele) { altitude = Number(ele.Value); if (!double.IsFinite(altitude.Value) || Math.Abs(altitude.Value) > 12000) throw new InvalidDataException(); }
                    points.Add(new(lat, lon, DateTimeOffset.UnixEpoch.AddSeconds(points.Count), id, altitude));
                }
            }
            if (points.Count < 2) throw new InvalidDataException();
            var map = new ExerciseRouteView(); results.Clear(); results.Add(map);
            map.Loaded += (_, _) => map.Update(points, false, true);
            var elevations = points.Where(p => p.AltitudeMeters != null).Select(p => p.AltitudeMeters!.Value).ToArray();
            double km = 0, climb = 0;
            for (var i = 1; i < points.Count; i++) {
                if (points[i].Segment != points[i-1].Segment) continue;
                km += Location.CalculateDistance(points[i-1].Latitude, points[i-1].Longitude, points[i].Latitude, points[i].Longitude, DistanceUnits.Kilometers);
                if (points[i].AltitudeMeters is { } h && points[i-1].AltitudeMeters is { } old) climb += Math.Max(0, h-old);
            }
            var estimate = points.Select(p => p.Segment).Distinct().Count() == 1 && elevations.Length == points.Count && km > 0 && km < 200
                ? $"\n路线长约 {km:F1} 公里，累计爬升约 {climb:F0} 米；参考移动耗时 {km/4 + climb/600:F1} 小时。按4公里/小时＋每爬升600米加1小时估算，不含休息，未考虑天气及路况；GPX高程噪声会影响结果。"
                : "\n高程缺失或路线不连续，暂不估算耗时。";
            status.Text = $"已导入 {points.Count} 个 WGS84 路线点，仅供地图预览，不计入运动记录。\n" + (elevations.Length > 0 ? $"路线最高海拔 {elevations.Max():F0} 米（文件值，不等于山峰高度）" : "文件未提供海拔") + estimate + "\n路面需向路线发布者核实。估时参考 Mountaineering Scotland 的路线规划方法。";
        } catch { status.Text = "无法导入：请选择有效 GPX 文件（不超过500万字符、2万个点），不支持外部实体。"; }
        finally { busy = false; }
    }
}
