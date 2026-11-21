using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace LinkoFamily;

internal sealed class DiningFoodMapsPage : ContentPage
{
    internal const string Endpoint = "/api/dining/food-maps";
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal sealed record Map(Guid Id, string Name, bool Followed);
    internal sealed record Point(Guid Id, string Name, string Category, string LocationText, string Description,
        double Latitude, double Longitude, double X, double Y, int Visits, double? Rating)
    {
        public DiningPlace Restaurant(string? system) => new("foodmap:" + Id, Name, LocationText, Latitude, Longitude, Category, system == "wgs84" ? "mapkit" : "amap", null, null, 0);
    }
    internal sealed record Snapshot(Guid Id, string Name, string? CoordinateSystem, long DataVersion, bool Full, Point[] Places);

    private readonly FamilyStore store;
    private readonly VerticalStackLayout rows = new() { Padding = 16, Spacing = 10 };
    private readonly Entry query = new() { Placeholder = "搜索饭圈名称", MaxLength = 100 };
    private readonly Label status = MomentStyle.Caption("");
    private readonly Func<Task> addresses;
    private readonly Func<Task> social;
    private readonly Func<DiningPlace, Task> navigate;
    private readonly Guid? initial;
    private bool busy;
    private Snapshot? snapshot;

    private sealed record Pending(string Path, JsonElement? Body, double? Latitude = null, double? Longitude = null);

    public DiningFoodMapsPage(FamilyStore store, Func<Task> addresses, Func<Task> social, Func<DiningPlace, Task> navigate, Guid? initial)
    {
        this.store = store;
        this.addresses = addresses;
        this.social = social;
        this.navigate = navigate;
        this.initial = initial;
        Title = "我的饭圈";
        Content = new ScrollView { Content = rows };
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        if (rows.Children.Count == 0) _ = Run(async () =>
        {
            await TrySync();
            if (initial is { } id) await Open(id); else await List();
        });
    }

    internal static async Task<Map[]> Discover(FamilyStore store, string query = "", bool followed = false) =>
        (await store.CallAsync(Endpoint + "/?followed=" + followed.ToString().ToLowerInvariant() + "&query=" + Uri.EscapeDataString(query)))
            .Deserialize<Map[]>(Json) ?? [];

    internal static async Task<Snapshot> Read(FamilyStore store, Guid id, Snapshot? baseline = null)
    {
        var value = (await store.CallAsync(Endpoint + "/" + id + (baseline is null ? "" : $"?since={baseline.DataVersion}")))
            .Deserialize<Snapshot>(Json) ?? throw new InvalidDataException();
        if (baseline is not null && !value.Full)
            value = value with { Places = baseline.Places.Concat(value.Places).GroupBy(p => p.Id).Select(g => g.Last()).OrderBy(p => p.Name).ToArray() };
        return value;
    }

    private string Cache(Guid id)
    {
        var owner = store.AccountProfile?.Subject ?? store.Profile?.Text("unifiedUserId");
        if (!store.Authenticated || string.IsNullOrWhiteSpace(owner)) throw new InvalidOperationException("请先登录。");
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(DiningAccount.Identity(owner))));
        var root = Path.Combine(FileSystem.AppDataDirectory, "FoodMaps", hash);
        Directory.CreateDirectory(root);
        return Path.Combine(root, id.ToString("D") + ".json");
    }

    private async Task List(bool nearby = false)
    {
        snapshot = null;
        rows.Clear();
        rows.Add(status);
        rows.Add(MomentStyle.Action("常用地址", () => _ = addresses()));
        rows.Add(MomentStyle.Action("饭搭子动态", () => _ = social()));
        rows.Add(query);
        rows.Add(MomentStyle.Action("搜索饭圈", () => _ = Run(() => List())));
        rows.Add(MomentStyle.Action("查找附近饭圈", () => _ = Run(() => List(true))));
        rows.Add(MomentStyle.Action("创建饭圈", () => _ = Run(Edit)));
        Map[] maps;
        try
        {
            if (nearby)
            {
                var gps = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(GeolocationAccuracy.Medium, TimeSpan.FromSeconds(15)))
                    ?? throw new InvalidOperationException("无法取得当前位置。");
                var center = await ConvertPosition(gps.Latitude, gps.Longitude);
                var path = FormattableString.Invariant($"{Endpoint}/?latitude={center.Latitude:R}&longitude={center.Longitude:R}");
                maps = (await store.CallAsync(path)).Deserialize<Map[]>(Json) ?? [];
            }
            else maps = await Discover(store, query.Text?.Trim() ?? "");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            status.Text = "离线，可打开已下载的地图。";
            maps = Directory.EnumerateFiles(Path.GetDirectoryName(Cache(Guid.Empty))!, "*.json")
                .Select(File.ReadAllText).Select(data => JsonSerializer.Deserialize<Snapshot>(data, Json))
                .OfType<Snapshot>().Select(m => new Map(m.Id, m.Name, true)).ToArray();
        }
        foreach (var map in maps)
        {
            var card = new VerticalStackLayout { Spacing = 4 };
            if (map.Followed) card.Add(MomentStyle.Action(map.Name, () => _ = Run(() => Open(map.Id))));
            else card.Add(MomentStyle.Title(map.Name, 16));
            card.Add(MomentStyle.Action(map.Followed ? "取消关注" : "关注", () => _ = Run(async () =>
            {
                await store.CallAsync(Endpoint + "/" + map.Id + "/follow", map.Followed ? HttpMethod.Delete : HttpMethod.Put);
                if (map.Followed) File.Delete(Cache(map.Id));
                await List();
            })));
            rows.Add(MomentStyle.Card(card, new Thickness(8)));
        }
    }

    private async Task Open(Guid id, bool delta = false)
    {
        var cache = Cache(id);
        var exists = File.Exists(cache);
        try
        {
            snapshot = await Read(store, id, delta && snapshot?.Id == id ? snapshot : null);
            if (exists) Save(snapshot);
        }
        catch (Exception ex) when (exists && ex is (HttpRequestException or TaskCanceledException))
        {
            snapshot = JsonSerializer.Deserialize<Snapshot>(File.ReadAllText(cache), Json);
            status.Text = "离线显示上次下载的数据。";
        }
        if (snapshot is not { } map) return;
        rows.Clear();
        rows.Add(status);
        rows.Add(MomentStyle.Title(map.Name, 22));
        rows.Add(MomentStyle.Action("检查更新", () => _ = Run(async () => { await TrySync(); await Open(id, true); })));
        rows.Add(MomentStyle.Action("添加美食地点", () => _ = Run(Edit)));
        rows.Add(MomentStyle.Action("返回饭圈列表", () => _ = Run(() => List())));
        foreach (var point in map.Places)
        {
            var rating = point.Rating is { } stars ? $" · ⭐ {stars:0.0} / 5" : "";
            rows.Add(MomentStyle.Action($"{point.Name} · {point.Visits} 人去过{rating}", () => _ = Run(() => Details(map.Id, point))));
            rows.Add(MomentStyle.Caption($"{point.Category} · {point.LocationText}"));
        }
    }

    private void Save(Snapshot map)
    {
        var file = Cache(map.Id);
        var temp = file + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(map, Json));
        File.Move(temp, file, true);
    }

    private async Task<(double Latitude, double Longitude)> ConvertPosition(double latitude, double longitude)
    {
        var response = await store.CallAsync("/api/dining/nearby", HttpMethod.Post, new { latitude, longitude, driving = false });
        var center = response.GetProperty("searchCenter");
        return (center.GetProperty("latitude").GetDouble(), center.GetProperty("longitude").GetDouble());
    }

    private async Task Edit()
    {
        var map = snapshot;
        var name = await DisplayPromptAsync(map is null ? "创建饭圈" : "添加美食地点", "填写名称", maxLength: 100);
        if (string.IsNullOrWhiteSpace(name)) return;
        string? category = null, locationText = null, description = null;
        if (map is not null)
        {
            category = await DisplayPromptAsync("美食类型", "例如路边摊、炒粉", maxLength: 80);
            if (string.IsNullOrWhiteSpace(category)) return;
            locationText = await DisplayPromptAsync("位置描述", "例如东门便利店旁", maxLength: 200);
            if (string.IsNullOrWhiteSpace(locationText)) return;
            description = await DisplayPromptAsync("美食介绍（选填）", "可留空", maxLength: 1000);
        }
        var place = await DiningPlacePickerPage.OpenAsync(this, store, false);
        if (place is null) return;
        var id = Guid.NewGuid();
        if (map is null)
        {
            var coordinate = await ConvertPosition(place.Latitude, place.Longitude);
            await store.CallAsync(Endpoint + "/", HttpMethod.Post, new
            {
                id, name, latitude = coordinate.Latitude, longitude = coordinate.Longitude, coordinateSystem = "gcj02"
            });
            await List();
        }
        else
        {
            var path = Endpoint + "/" + map.Id + "/places";
            var pending = map.CoordinateSystem == "wgs84"
                ? new Pending(path, JsonSerializer.SerializeToElement(new { id, name, category, locationText, description,
                    latitude = place.Latitude, longitude = place.Longitude, coordinateSystem = "wgs84" }, Json))
                : new Pending(path, JsonSerializer.SerializeToElement(new { id, name, category, locationText, description }, Json),
                    place.Latitude, place.Longitude);
            if (await Submit(pending))
                await Open(map.Id, true);
        }
    }

    private async Task<bool> Submit(Pending item)
    {
        var file = Path.ChangeExtension(Cache(Guid.Empty), ".outbox");
        var pending = ReadPending(file);
        pending.Add(item);
        WritePending(file, pending);
        return await TrySync();
    }

    private async Task<bool> TrySync()
    {
        var session = store.SessionVersion;
        var file = Path.ChangeExtension(Cache(Guid.Empty), ".outbox");
        var pending = ReadPending(file);
        try
        {
            while (pending.Count > 0)
            {
                if (session != store.SessionVersion) return false;
                var item = pending[0];
                object? body = item.Body;
                if (item.Latitude is { } lat && item.Longitude is { } lon && item.Body is { } raw)
                {
                    var center = await ConvertPosition(lat, lon);
                    var fields = raw.EnumerateObject().ToDictionary(x => x.Name, x => (object)x.Value);
                    fields["latitude"] = center.Latitude;
                    fields["longitude"] = center.Longitude;
                    fields["coordinateSystem"] = "gcj02";
                    body = fields;
                }
                if (session != store.SessionVersion) return false;
                try { await store.CallAsync(item.Path, HttpMethod.Put, body); }
                catch (FamilyApiException error) when (error.StatusCode is System.Net.HttpStatusCode.BadRequest
                    or System.Net.HttpStatusCode.NotFound or System.Net.HttpStatusCode.Conflict)
                {
                    status.Text = error.Message;
                }
                if (session != store.SessionVersion) return false;
                pending.RemoveAt(0);
                WritePending(file, pending);
            }
            return true;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            status.Text = "已保存，联网后可同步。";
            return false;
        }
    }

    private static List<Pending> ReadPending(string file) => File.Exists(file)
        ? JsonSerializer.Deserialize<List<Pending>>(File.ReadAllText(file), Json) ?? [] : [];

    private static void WritePending(string file, List<Pending> pending)
    {
        var temporary = file + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(pending, Json));
        File.Move(temporary, file, true);
    }

    private async Task Details(Guid id, Point point)
    {
        var path = Endpoint + "/" + id + "/places/" + point.Id;
        var title = string.IsNullOrWhiteSpace(point.Description) ? point.Name : $"{point.Name}\n{point.Description}";
        var choice = await DisplayActionSheetAsync(title, "取消", null, "我去过", "提交评分", "查看在线点评", "带我去");
        if (choice == "带我去") { await navigate(point.Restaurant(snapshot?.CoordinateSystem)); return; }
        if (choice == "我去过") { if (!await Submit(new Pending(path + "/visit", null))) return; }
        else if (choice == "提交评分")
        {
            var rating = await DisplayActionSheetAsync("评分", "取消", null, "1", "2", "3", "4", "5");
            if (!int.TryParse(rating, out var stars)) return;
            var note = await DisplayPromptAsync("点评（选填）", "可留空直接提交", "提交", "取消", maxLength: 1000);
            if (note is null) return;
            if (!await Submit(new Pending(path + "/review", JsonSerializer.SerializeToElement(new { stars, note }, Json)))) return;
        }
        else if (choice == "查看在线点评")
        {
            var comments = (await store.CallAsync(path + "/reviews")).EnumerateArray()
                .Select(x => x.GetProperty("note").GetString()).ToArray();
            await DisplayAlertAsync(point.Name, comments.Length == 0 ? "暂无文字点评。" : string.Join("\n\n", comments), "完成");
            return;
        }
        else return;
        await Open(id, true);
    }

    private async Task Run(Func<Task> action)
    {
        if (busy) return;
        busy = true;
        status.Text = "";
        try { await action(); }
        catch (Exception ex) { status.Text = ex is FamilyApiException ? ex.Message : "操作暂未完成，请检查网络后重试。"; }
        finally { busy = false; }
    }

}
