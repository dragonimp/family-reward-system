using System.Globalization;
using System.Text.Json.Nodes;

namespace LinkoFamily;

internal sealed class BeveragePage : ContentPage
{
    private readonly FamilyStore store;
    private readonly VerticalStackLayout rows = new() { Padding = 18, Spacing = 12 };
    private readonly Picker section = new() { ItemsSource = new[] { "喝点啥", "拍照记一杯", "我的酒柜", "我的饮品屋" }, SelectedIndex = 1 };
    private readonly Label status = MomentStyle.Caption("");
    private readonly Entry name = new() { Placeholder = "饮品名称" };
    private readonly Picker category = new() { Title = "分类", ItemsSource = new[] { "酒类", "非酒精", "待确认" } };
    private readonly string[] categories = ["alcoholic", "nonalcoholic", "unknown"];
    private readonly Picker rating = new() { Title = "评分", ItemsSource = new[] { "不评分", "★", "★★", "★★★", "★★★★", "★★★★★" }, SelectedIndex = 0 };
    private readonly Entry note = new() { Placeholder = "一句话评价", MaxLength = 500 };
    private readonly Entry place = new() { Placeholder = "饮用地点", MaxLength = 160 };
    private readonly DatePicker day = new() { Date = DateTime.Today };
    private readonly Entry search = new() { Placeholder = "搜索名称、品牌、品类" };
    private readonly Dictionary<string, Entry> details = new()
    {
        ["brand"] = new Entry { Placeholder = "品牌" }, ["kind"] = new Entry { Placeholder = "品类" },
        ["origin"] = new Entry { Placeholder = "产地" }, ["producer"] = new Entry { Placeholder = "生产商" },
        ["size"] = new Entry { Placeholder = "规格" }, ["alcoholPercent"] = new Entry { Placeholder = "酒精度" },
        ["vintage"] = new Entry { Placeholder = "年份" }
    };
    private readonly List<string> photos = [];
    private JsonArray items = [];
    private Guid recordId = Guid.NewGuid();
    private string? profileId;
    private int recommendation;
    private bool busy;
    private string? recognitionRoute;

    public BeveragePage(FamilyStore store)
    {
        this.store = store;
        Title = "整两口";
        BackgroundColor = MomentStyle.Background;
        SafeAreaEdges = SafeAreaEdges.All;
        Content = new ScrollView { Content = rows };
        section.SelectedIndexChanged += (_, _) => Render();
        search.Completed += (_, _) => Render();
        Render();
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await Run(Load);
    }

    private static string Value(JsonNode? row, string key) => KitchenPersonal.Text(row, key);
    private async Task<JsonNode?> Call(string route, HttpMethod? method = null, object? body = null) =>
        JsonNode.Parse((await store.CallAsync("/api/beverages" + route, method, body)).GetRawText());

    private async Task Load() => items = KitchenPersonal.Array(await Call(""), "items");

    private async Task Run(Func<Task> action)
    {
        if (busy) return;
        busy = true;
        rows.IsEnabled = false;
        status.Text = "处理中…";
        try { await action(); if (status.Text == "处理中…") status.Text = ""; }
        catch (Exception error) { status.Text = error is FamilyApiException ? error.Message : "操作未完成，可重试或继续手动填写。"; }
        finally { busy = false; rows.IsEnabled = true; Render(); }
    }

    private void Render()
    {
        rows.Clear();
        rows.Add(section);
        rows.Add(status);
        if (section.SelectedIndex == 0)
        {
            var suggestions = items.OrderByDescending(Score).Select(item => Value(item, "name")).ToArray();
            if (suggestions.Length == 0) suggestions = ["茉莉花茶", "冰拿铁", "气泡水", "乌龙奶茶"];
            rows.Add(MomentStyle.Title(suggestions[recommendation % suggestions.Length], 24));
            rows.Add(MomentStyle.Action("换一杯", () => { recommendation++; Render(); }, true));
        }
        else if (section.SelectedIndex == 1)
        {
            if (photos.Count < 6) rows.Add(MomentStyle.Action("拍照或从相册选择", () => _ = Run(AddPhoto)));
            rows.Add(MomentStyle.Caption($"已添加 {photos.Count} 张照片"));
            rows.Add(name);
            rows.Add(category);
            foreach (var entry in details.Values) rows.Add(entry);
            rows.Add(rating);
            rows.Add(note);
            rows.Add(place);
            rows.Add(day);
            rows.Add(MomentStyle.Action("确认归档", () => _ = Run(Save), true));
        }
        else
        {
            rows.Add(search);
            rows.Add(MomentStyle.Action("搜索", Render));
            var type = categories[section.SelectedIndex == 2 ? 0 : 1];
            foreach (var item in items.Where(item => (Value(item, "category") == type || (type == "nonalcoholic" && Value(item, "category") == "unknown")) &&
                (string.IsNullOrWhiteSpace(search.Text) || new[] { "name", "brand", "kind" }.Any(key => Value(item, key).Contains(search.Text, StringComparison.CurrentCultureIgnoreCase)))))
            {
                var card = new VerticalStackLayout { Spacing = 8 };
                var favorite = item?["favorite"]?.GetValue<bool>() == true;
                card.Add(MomentStyle.Title(Value(item, "name"), 18));
                if (Value(item, "category") == "unknown") card.Add(MomentStyle.Caption("分类待确认"));
                card.Add(MomentStyle.Action(favorite ? "取消收藏" : "收藏", () => _ = Run(async () =>
                {
                    await store.CallAsync($"/api/beverages/{Value(item, "id")}/favorite", HttpMethod.Put, new { favorite = !favorite });
                    await Load();
                })));
                foreach (var record in KitchenPersonal.Array(item, "records"))
                {
                    card.Add(MomentStyle.Caption(string.Join(" · ", new[] { "consumedOn", "rating", "note", "place" }.Select(key => Value(record, key)).Where(value => value.Length > 0))));
                    card.Add(MomentStyle.Action("编辑记录", () => Edit(item, record)));
                    card.Add(MomentStyle.Action("删除记录", async () =>
                    {
                        if (!await DisplayAlertAsync("删除饮用记录", "确认删除这条记录？", "删除", "取消")) return;
                        await Run(async () =>
                        {
                            await store.CallAsync($"/api/beverages/records/{Value(record, "id")}", HttpMethod.Delete);
                            await Load();
                        });
                    }));
                }
                rows.Add(MomentStyle.Card(card));
            }
        }
    }

    private static double Score(JsonNode? item) => KitchenPersonal.Array(item, "records")
        .Select(record => int.TryParse(Value(record, "rating"), out var stars) ? stars : 0)
        .Where(stars => stars > 0).DefaultIfEmpty(0).Average() + (item?["favorite"]?.GetValue<bool>() == true ? 1 : 0);

    private void Edit(JsonNode? profile, JsonNode? record)
    {
        if (!Guid.TryParse(Value(record, "id"), out recordId)) return;
        recognitionRoute = null;
        profileId = Value(profile, "id");
        Apply(profile, false);
        rating.SelectedIndex = int.TryParse(Value(record, "rating"), out var stars) ? stars : 0;
        note.Text = Value(record, "note");
        place.Text = Value(record, "place");
        day.Date = DateTime.TryParseExact(Value(record, "consumedOn"), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed) ? parsed : DateTime.Today;
        photos.Clear();
        photos.AddRange(KitchenPersonal.Array(record, "photoIds").Select(x => x!.ToString()));
        section.SelectedIndex = 1;
        Render();
    }

    private void Apply(JsonNode? profile, bool onlyEmpty)
    {
        if (!onlyEmpty || string.IsNullOrWhiteSpace(name.Text)) name.Text = Value(profile, "name");
        if (!onlyEmpty || category.SelectedIndex is < 0 or 2) category.SelectedIndex = Array.IndexOf(categories, Value(profile, "category"));
        foreach (var (key, entry) in details)
            if (!onlyEmpty || string.IsNullOrWhiteSpace(entry.Text)) entry.Text = Value(profile, key);
    }

    private async Task AddPhoto()
    {
        if (photos.Count >= 6 || await KitchenPersonal.Photo(this) is not { } data) return;
        var media = Guid.NewGuid().ToString("D");
        var route = "/recognitions/" + Guid.NewGuid().ToString("D");
        await KitchenPersonal.Upload(store, media, "recipe", data);
        photos.Add(media);
        recognitionRoute = route;
        status.Text = "正在识别，可先手动填写并归档。";
        _ = Recognize(route, media);
    }

    private async Task Recognize(string route, string media)
    {
        try
        {
            await Call(route, HttpMethod.Post, new { mediaId = media });
            for (var i = 0; i < 95 && recognitionRoute == route; i++)
            {
                var task = await Call(route);
                if (recognitionRoute != route) return;
                if (Value(task, "state") == "completed")
                {
                    var draft = task?["result"];
                    Apply(draft, true);
                    status.Text = string.IsNullOrWhiteSpace(Value(draft, "name"))
                        ? "未识别出饮品名称，请输入名称后归档。" : "请确认识别结果，可手动修改。";
                    return;
                }
                if (Value(task, "state") == "failed") break;
                await Task.Delay(2000);
            }
        }
        catch (Exception)
        {
            // Recognition is optional once the photo has been uploaded.
        }
        if (recognitionRoute == route) status.Text = "识别未完成，照片已保留，请输入饮品名称后归档。";
    }

    private async Task Save()
    {
        var title = name.Text?.Trim();
        if (string.IsNullOrEmpty(title))
        {
            status.Text = "请填写饮品名称。";
            return;
        }
        var selectedCategory = category.SelectedIndex >= 0 ? categories[category.SelectedIndex] : "unknown";
        var draft = new Dictionary<string, object?> { ["name"] = title, ["category"] = selectedCategory };
        foreach (var (key, entry) in details)
        {
            if (string.IsNullOrWhiteSpace(entry.Text)) continue;
            if (key == "alcoholPercent")
            {
                if (!decimal.TryParse(entry.Text, NumberStyles.Number, CultureInfo.InvariantCulture, out var value) || value is < 0 or > 100)
                { status.Text = "请输入有效酒精度。"; return; }
                draft[key] = value;
            }
            else if (key == "vintage")
            {
                if (!int.TryParse(entry.Text, out var value) || value is < 1000 or > 9999)
                { status.Text = "请输入有效年份。"; return; }
                draft[key] = value;
            }
            else draft[key] = entry.Text;
        }
        recognitionRoute = null;
        await Call($"/records/{recordId:D}", HttpMethod.Put, new
        {
            beverageId = profileId, beverage = draft, consumedOn = (day.Date ?? DateTime.Today).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            rating = rating.SelectedIndex > 0 ? (int?)rating.SelectedIndex : null, note = note.Text, place = place.Text, photoIds = photos.ToArray()
        });
        var target = category.SelectedIndex == 0 ? 2 : 3;
        recordId = Guid.NewGuid();
        profileId = null;
        photos.Clear();
        name.Text = note.Text = place.Text = "";
        foreach (var entry in details.Values) entry.Text = "";
        category.SelectedIndex = -1;
        rating.SelectedIndex = 0;
        day.Date = DateTime.Today;
        section.SelectedIndex = target;
        await Load();
    }
}
