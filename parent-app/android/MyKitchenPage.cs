using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Maui.Graphics.Platform;

namespace LinkoFamily;

internal static class KitchenPersonal
{
    public static string Text(JsonNode? n, string key) => n?[key]?.ToString() ?? "";
    public static JsonArray Array(JsonNode? n, string key) => n?[key] as JsonArray ?? new();
    public static async Task<JsonObject> Get(FamilyStore store, string path) => JsonNode.Parse((await store.CallAsync("/api/kitchen/" + path)).GetRawText())!.AsObject();
    public static async Task Run(ContentPage page, Func<Task> action) { try { await action(); } catch (Exception e) { await page.DisplayAlertAsync("我的厨房", e is FamilyApiException ? e.Message : "操作未完成，请检查网络或权限后重试。", "知道了"); } }
    public static async Task<byte[]?> Photo(ContentPage page)
    {
        var choice = await page.DisplayActionSheetAsync("选择图片", "取消", null, "拍照", "从相册选择");
        FileResult? result = choice switch { "拍照" => await MediaPicker.Default.CapturePhotoAsync(), "从相册选择" => (await MediaPicker.Default.PickPhotosAsync()).FirstOrDefault(), _ => null };
        if (result is null) return null;
        await using var stream = await result.OpenReadAsync();
        if (stream.CanSeek && stream.Length > 30 * 1024 * 1024) throw new FamilyApiException("请选择30MB以内的图片。");
        using var image = PlatformImage.FromStream(stream);
        using var sized = image.Downsize(1600, true);
        using var output = new MemoryStream();
        sized.Save(output, Microsoft.Maui.Graphics.ImageFormat.Jpeg, .85f);
        if (output.Length > 8 * 1024 * 1024) throw new FamilyApiException("图片过大，请重试。");
        return output.ToArray();
    }
    public static async Task Upload(FamilyStore store, string id, string purpose, byte[] data) => _ = await store.CallAsync("/api/kitchen/media", HttpMethod.Post, new { id, purpose, base64 = Convert.ToBase64String(data) });
    public static void Image(VerticalStackLayout rows, FamilyStore store, string id)
    {
        if (!Guid.TryParse(id, out _)) return;
        var image = new Image { HeightRequest = 180, Aspect = Aspect.AspectFit }; rows.Add(image);
        _ = Load(); async Task Load() { try { var data = await store.KitchenImageAsync(id); image.Source = ImageSource.FromStream(() => new MemoryStream(data)); } catch { image.IsVisible = false; } }
    }
    public static ContentPage Page(string title, VerticalStackLayout rows) => new() { Title = title, BackgroundColor = MomentStyle.Background, SafeAreaEdges = SafeAreaEdges.All, Content = new ScrollView { Content = rows } };
    public static JsonObject Draft() => new() { ["name"] = "", ["ingredients"] = new JsonArray(new JsonObject { ["name"] = "", ["quantity"] = "", ["unit"] = "" }), ["steps"] = new JsonArray(new JsonObject { ["number"] = 1, ["instruction"] = "" }), ["preparation"] = new JsonArray(), ["notes"] = new JsonArray() };
}

public sealed class MyKitchenPage : ContentPage
{
    public MyKitchenPage(FamilyStore store)
    {
        Title = "我的厨房"; BackgroundColor = MomentStyle.Background;
        var rows = new VerticalStackLayout { Padding = 20, Spacing = 16 };
        rows.Add(MomentStyle.Action("我的菜谱", () => _ = Navigation.PushAsync(new MyKitchenRecipesPage(store))));
        rows.Add(MomentStyle.Action("做过的菜", () => _ = Navigation.PushAsync(new KitchenCookingHistoryPage(store))));
        Content = rows;
    }
}
public sealed class MyKitchenRecipesPage : ContentPage
{
    readonly FamilyStore store;
    readonly VerticalStackLayout rows = new() { Spacing = 14 };
    readonly SearchBar search = new() { Placeholder = "搜索菜谱" };
    readonly Picker filter = new() { Title = "分类", ItemsSource = new[] { "全部", "星标常用", "我上传的" }, SelectedIndex = 0 };
    int request;
    public MyKitchenRecipesPage(FamilyStore store)
    {
        this.store = store; Title = "我的菜谱"; BackgroundColor = MomentStyle.Background;
        var body = new VerticalStackLayout { Padding = 20, Spacing = 12 }; body.Add(filter); body.Add(search); body.Add(rows);
        Content = new ScrollView { Content = body };
        ToolbarItems.Add(new ToolbarItem("＋ 上传菜谱", null, () => _ = Navigation.PushAsync(new KitchenRecipeEditorPage(store))));
        filter.SelectedIndexChanged += (_, _) => _ = Load(); search.SearchButtonPressed += (_, _) => _ = Load(); search.TextChanged += (_, e) => { if (string.IsNullOrEmpty(e.NewTextValue)) _ = Load(); };
    }
    protected override void OnAppearing() { base.OnAppearing(); _ = Load(); }
    async Task Load() => await KitchenPersonal.Run(this, async () => {
        var attempt = ++request;
        var f = filter.SelectedIndex switch { 1 => "starred", 2 => "uploaded", _ => "" };
        var data = await KitchenPersonal.Get(store, "recipes?filter=" + f + "&q=" + Uri.EscapeDataString(search.Text ?? "")); if (attempt != request) return;
        rows.Clear(); foreach (var item in KitchenPersonal.Array(data, "items")) {
            var id = KitchenPersonal.Text(item, "id"); var kind = KitchenPersonal.Text(item, "kind");
            var card = new VerticalStackLayout { Spacing = 6 };
            KitchenPersonal.Image(card, store, KitchenPersonal.Text(item, "originalMediaId"));
            if (Uri.TryCreate(KitchenPersonal.Text(item?["recipe"], "coverImage"), UriKind.Absolute, out var cover) && cover.Scheme == "https") card.Add(new Image { Source = cover.ToString(), HeightRequest = 140, Aspect = Aspect.AspectFit });
            card.Add(MomentStyle.Title(KitchenPersonal.Text(item, "name"), 20));
            card.Add(MomentStyle.Caption((KitchenPersonal.Text(item, "starred") == "true" ? "★ · " : "") + "已做 " + KitchenPersonal.Text(item, "madeCount") + " 次"));
            card.Add(MomentStyle.Action("查看详情", () => _ = Navigation.PushAsync(new MyKitchenRecipePage(store, id, kind)))); rows.Add(card);
        }
        if (rows.Count == 0) rows.Add(MomentStyle.Caption("还没有菜谱，可以上传、手动创建或收藏公共菜谱。"));
    });
}
public sealed class MyKitchenRecipePage : ContentPage
{
    readonly FamilyStore store; readonly string id, kind;
    readonly VerticalStackLayout rows = new() { Padding = 20, Spacing = 14 };
    JsonObject? meta;
    public MyKitchenRecipePage(FamilyStore store, string id, string kind) { this.store = store; this.id = id; this.kind = kind; Title = "菜谱详情"; BackgroundColor = MomentStyle.Background; Content = new ScrollView { Content = rows }; }
    protected override void OnAppearing() { base.OnAppearing(); _ = Load(); }
    async Task Load() => await KitchenPersonal.Run(this, async () => {
        meta = await KitchenPersonal.Get(store, $"recipes/{id}?kind={kind}"); var recipe = meta["recipe"]!; rows.Clear();
        rows.Add(MomentStyle.Title(KitchenPersonal.Text(recipe, "name"), 26)); KitchenPersonal.Image(rows, store, KitchenPersonal.Text(meta, "originalMediaId"));
        if (Uri.TryCreate(KitchenPersonal.Text(recipe, "coverImage"), UriKind.Absolute, out var cover) && cover.Scheme == "https") rows.Add(new Image { Source = cover.ToString(), HeightRequest = 180, Aspect = Aspect.AspectFit });
        rows.Add(MomentStyle.Caption("已做 " + KitchenPersonal.Text(meta, "madeCount") + " 次"));
        rows.Add(MomentStyle.Action(KitchenPersonal.Text(meta, "starred") == "true" ? "★ 取消星标" : "☆ 星标常用", () => _ = Relationship(true)));
        if (kind == "public") rows.Add(MomentStyle.Action(KitchenPersonal.Text(meta, "favorite") == "true" ? "取消收藏" : "收藏菜谱", () => _ = Relationship(false)));
        rows.Add(MomentStyle.Action("做菜打卡", () => _ = Navigation.PushAsync(new KitchenCookingEditorPage(store, id))));
        rows.Add(MomentStyle.Action("做菜历史", () => _ = Navigation.PushAsync(new KitchenCookingHistoryPage(store, id))));
        rows.Add(MomentStyle.Title("食材", 20)); foreach (var i in KitchenPersonal.Array(recipe, "ingredients")) rows.Add(new Label { Text = KitchenPersonal.Text(i, "name") + " " + KitchenPersonal.Text(i, "quantity") + " " + KitchenPersonal.Text(i, "unit") });
        rows.Add(MomentStyle.Title("准备工作", 20)); foreach (var i in KitchenPersonal.Array(recipe, "preparation")) rows.Add(new Label { Text = i?.ToString() });
        rows.Add(MomentStyle.Title("制作步骤", 20)); foreach (var step in KitchenPersonal.Array(recipe, "steps")) {
            rows.Add(MomentStyle.Title(KitchenPersonal.Text(step, "number") + ". " + KitchenPersonal.Text(step, "action"), 18)); rows.Add(new Label { Text = KitchenPersonal.Text(step, "instruction") });
            rows.Add(MomentStyle.Caption(string.Join(" · ", new[] { KitchenPersonal.Text(step, "duration"), KitchenPersonal.Text(step, "heat"), KitchenPersonal.Text(step, "notes") }.Where(x => x.Length > 0))));
        }
        rows.Add(MomentStyle.Title("注意事项", 20)); foreach (var i in KitchenPersonal.Array(recipe, "notes")) rows.Add(new Label { Text = i?.ToString() });
        rows.Add(MomentStyle.Caption(KitchenPersonal.Text(meta, "sourceText")));
        if (kind == "private") {
            rows.Add(MomentStyle.Action("编辑菜谱", () => _ = Navigation.PushAsync(new KitchenRecipeEditorPage(store, meta))));
            rows.Add(MomentStyle.Action("删除菜谱", () => _ = KitchenPersonal.Run(this, async () => { if (await DisplayAlertAsync("删除菜谱？", "做菜历史仍保留。", "删除", "取消")) { await store.CallAsync("/api/kitchen/recipes/" + id, HttpMethod.Delete); await Navigation.PopAsync(); } })));
        }
    });
    async Task Relationship(bool star) => await KitchenPersonal.Run(this, async () => {
        var favorite = KitchenPersonal.Text(meta, "favorite") == "true"; var starred = KitchenPersonal.Text(meta, "starred") == "true";
        await store.CallAsync($"/api/kitchen/recipes/{id}/relationship", HttpMethod.Put, new { kind, favorite = star ? favorite : !favorite, starred = star ? !starred : starred }); await Load();
    });
}
public sealed class KitchenRecipeEditorPage : ContentPage
{
    readonly FamilyStore store;
    readonly VerticalStackLayout body = new() { Padding = 20, Spacing = 12 };
    JsonObject recipe, meta; string id, mediaID = Guid.NewGuid().ToString("D"); string? taskID;
    byte[]? pending; JsonObject? recognized; int pollVersion; bool busy;
    public KitchenRecipeEditorPage(FamilyStore store, JsonObject? initial = null)
    {
        this.store = store; meta = initial?.DeepClone().AsObject() ?? new(); recipe = meta["recipe"]?.DeepClone().AsObject() ?? KitchenPersonal.Draft(); id = KitchenPersonal.Text(recipe, "recipeId"); if (!Guid.TryParse(id, out _)) id = Guid.NewGuid().ToString("D");
        Title = initial is null ? "上传菜谱" : "编辑菜谱"; BackgroundColor = MomentStyle.Background; Content = new ScrollView { Content = body }; Render();
    }
    protected override void OnAppearing() { base.OnAppearing(); if (taskID != null) _ = Poll(taskID); }
    protected override void OnDisappearing() { ++pollVersion; base.OnDisappearing(); }
    Entry Field(VerticalStackLayout target, string label, string value, Action<string> change) { var entry = new Entry { Placeholder = label, Text = value }; target.Add(new Label { Text = label, FontSize = 13, TextColor = Colors.Gray }); target.Add(entry); entry.TextChanged += (_, e) => change(e.NewTextValue ?? ""); return entry; }
    void Render(string message = "")
    {
        body.Clear();
        body.Add(MomentStyle.Caption("个人菜谱默认私有。可拍照、从相册识别，或直接手动填写。"));
        body.Add(MomentStyle.Action("选择菜谱图片", () => _ = KitchenPersonal.Run(this, async () => { var data = await KitchenPersonal.Photo(this); if (data != null) { pending = data; mediaID = Guid.NewGuid().ToString("D"); Render("图片已选择，可识别或手动填写后保存。"); } })));
        if (pending != null) { body.Add(new Image { Source = ImageSource.FromStream(() => new MemoryStream(pending)), HeightRequest = 180 }); body.Add(MomentStyle.Action("AI 识别图片 / 重试", () => _ = Recognize())); }
        else KitchenPersonal.Image(body, store, KitchenPersonal.Text(meta, "originalMediaId"));
        body.Add(MomentStyle.Action("继续最近的识别记录", () => _ = Recent()));
        if (taskID != null) body.Add(MomentStyle.Action("查询识别结果", () => _ = Poll(taskID)));
        if (recognized != null) body.Add(MomentStyle.Action("应用识别结果（替换当前填写内容）", () => { recipe = recognized["draft"]!.DeepClone().AsObject(); meta["originalMediaId"] = recognized["mediaId"]?.DeepClone(); meta["recognitionId"] = recognized["id"]?.DeepClone(); meta["uncertainFields"] = recognized["uncertainFields"]?.DeepClone(); recognized = null; Render("请逐项核对所有识别字段。"); }));
        if (message.Length > 0) body.Add(MomentStyle.Caption(message));
        if (meta["uncertainFields"] is JsonArray uncertain) body.Add(MomentStyle.Caption("待确认：" + string.Join("、", uncertain.Select(x => x?.ToString()))));
        foreach (var key in new[] { "name", "duration", "servings", "difficulty" }) {
            var label = key switch { "name" => "菜名", "duration" => "预计分钟数（未知留空）", "servings" => "人数（未知留空）", _ => "难度（未知留空）" };
            Field(body, label, KitchenPersonal.Text(recipe, key), value => recipe[key] = value);
        }
        Field(body, "来源及使用授权说明", KitchenPersonal.Text(meta, "sourceText"), value => meta["sourceText"] = value);
        body.Add(MomentStyle.Title("食材与用量", 20));
        var ingredients = KitchenPersonal.Array(recipe, "ingredients"); foreach (var node in ingredients.ToArray()) {
            if (node is not JsonObject item) continue;
            var card = new VerticalStackLayout { Spacing = 4 };
            foreach (var key in new[] { "name", "quantity", "unit" }) Field(card, key switch { "name" => "食材", "quantity" => "用量（未知留空）", _ => "单位" }, KitchenPersonal.Text(item, key), value => item[key] = value);
            card.Add(MomentStyle.Action("移除此食材", () => { ingredients.Remove(item); Render(); })); body.Add(card);
        }
        body.Add(MomentStyle.Action("添加食材", () => { ingredients.Add(new JsonObject { ["name"] = "", ["quantity"] = "", ["unit"] = "" }); Render(); }));
        Lines("准备工作 · 每行一项", "preparation");
        body.Add(MomentStyle.Title("制作步骤", 20)); var steps = KitchenPersonal.Array(recipe, "steps");
        for (var index = 0; index < steps.Count; index++) {
            if (steps[index] is not JsonObject step) continue; var at = index;
            var card = new VerticalStackLayout { Spacing = 6 }; card.Add(MomentStyle.Title("步骤 " + (index + 1), 18));
            foreach (var key in new[] { "action", "instruction", "duration", "heat", "notes" }) Field(card, key switch { "action" => "操作名称", "instruction" => "操作说明（必填）", "duration" => "时间", "heat" => "火候", _ => "注意事项" }, KitchenPersonal.Text(step, key), value => step[key] = value);
            Field(card, "涉及食材，用、分隔", string.Join("、", KitchenPersonal.Array(step, "ingredients").Select(x => x?.ToString())), value => step["ingredients"] = new JsonArray(value.Split('、', StringSplitOptions.RemoveEmptyEntries).Select(x => (JsonNode?)JsonValue.Create(x)).ToArray()));
            if (at > 0) card.Add(MomentStyle.Action("上移", () => { steps.RemoveAt(at); steps.Insert(at - 1, step); Render(); }));
            card.Add(MomentStyle.Action("删除步骤", () => { steps.Remove(step); Render(); })); body.Add(card);
        }
        body.Add(MomentStyle.Action("添加步骤", () => { steps.Add(new JsonObject { ["instruction"] = "" }); Render(); }));
        Lines("注意事项 · 每行一项", "notes");
        var confirm = new CheckBox(); body.Add(new Label { Text = "我已核对食材、步骤、火候及安全提示。AI 识别内容必须逐项确认。" }); body.Add(confirm);
        var save = MomentStyle.Action("保存到我的菜谱", () => _ = Save(), true); save.IsEnabled = false; confirm.CheckedChanged += (_, e) => save.IsEnabled = e.Value && !busy; body.Add(save);
    }
    void Lines(string label, string key) { body.Add(MomentStyle.Caption(label)); var edit = new Editor { Text = string.Join("\n", KitchenPersonal.Array(recipe, key).Select(x => x?.ToString())), AutoSize = EditorAutoSizeOption.TextChanges, MinimumHeightRequest = 70 }; edit.TextChanged += (_, e) => recipe[key] = new JsonArray((e.NewTextValue ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries).Select(x => (JsonNode?)JsonValue.Create(x)).ToArray()); body.Add(edit); }
    async Task Recognize() { if (busy || pending == null) return; busy = true; body.IsEnabled = false; await KitchenPersonal.Run(this, async () => { await KitchenPersonal.Upload(store, mediaID, "recipe", pending); meta["originalMediaId"] = mediaID; var id = Guid.NewGuid().ToString("D"); await store.CallAsync("/api/kitchen/recognitions", HttpMethod.Post, new { id, mediaId = mediaID }); taskID = id; Render("识别处理中，离开页面后任务仍会执行。"); _ = Poll(id); }); busy = false; body.IsEnabled = true; }
    async Task Poll(string task) {
        var attempt = ++pollVersion;
        try { while (attempt == pollVersion) {
            var row = await KitchenPersonal.Get(store, "recognitions/" + task); if (attempt != pollVersion) return;
            var state = KitchenPersonal.Text(row, "state"); if (state == "completed" && row["result"] is JsonObject result && result["draft"] is JsonObject draft) { recognized = result.DeepClone().AsObject(); recognized["mediaId"] = row["mediaId"]?.DeepClone(); recognized["id"] = task; taskID = null; Render("识别完成，点击应用后核对。当前填写内容尚未改变。"); return; }
            if (state == "failed") { taskID = null; Render(KitchenPersonal.Text(row, "error")); return; }
            await Task.Delay(4000);
        } } catch { if (attempt == pollVersion) Render("识别状态暂时无法读取，可稍后从识别记录继续。"); }
    }
    async Task Recent() => await KitchenPersonal.Run(this, async () => {
        var data = await KitchenPersonal.Get(store, "recognitions"); var items = KitchenPersonal.Array(data, "items").ToArray();
        var labels = items.Select((item, i) => (i + 1) + " · " + KitchenPersonal.Text(item, "state") + " · " + (DateTimeOffset.TryParse(KitchenPersonal.Text(item, "createdAt"), out var time) ? time.ToLocalTime().ToString("g") : "")).ToArray();
        var choice = await DisplayActionSheetAsync("识别记录（当地时间）", "取消", null, labels); var index = System.Array.IndexOf(labels, choice); if (index >= 0) { taskID = KitchenPersonal.Text(items[index], "id"); _ = Poll(taskID); }
    });
    async Task Save() {
        if (busy) return; busy = true; body.IsEnabled = false;
        await KitchenPersonal.Run(this, async () => {
            if (pending != null && KitchenPersonal.Text(meta, "originalMediaId") != mediaID) { await KitchenPersonal.Upload(store, mediaID, "recipe", pending); meta["originalMediaId"] = mediaID; meta["recognitionId"] = null; }
            var steps = KitchenPersonal.Array(recipe, "steps"); for (var i = 0; i < steps.Count; i++) steps[i]!["number"] = i + 1;
            foreach (var key in new[] { "duration", "servings" }) recipe[key] = int.TryParse(KitchenPersonal.Text(recipe, key), out var n) && n > 0 ? JsonValue.Create(n) : null;
            var payload = new JsonObject { ["recipe"] = recipe.DeepClone(), ["confirmed"] = true, ["version"] = int.TryParse(KitchenPersonal.Text(meta, "version"), out var version) ? version : 0, ["originalMediaId"] = meta["originalMediaId"]?.DeepClone(), ["recognitionId"] = meta["recognitionId"]?.DeepClone(), ["sourceText"] = KitchenPersonal.Text(meta, "sourceText") };
            await store.CallAsync("/api/kitchen/recipes/" + id, HttpMethod.Put, payload); await Navigation.PopAsync();
        }); busy = false; body.IsEnabled = true;
    }
}
public sealed class KitchenCookingEditorPage : ContentPage
{
    readonly FamilyStore store; readonly string? initial;
    readonly VerticalStackLayout body = new() { Padding = 20, Spacing = 14 };
    readonly Picker picker = new() { Title = "关联菜谱" }; readonly DatePicker day = new() { Date = DateTime.Today }; readonly Editor note = new() { Placeholder = "备注", AutoSize = EditorAutoSizeOption.TextChanges };
    readonly Image image = new() { HeightRequest = 180, Aspect = Aspect.AspectFit };
    JsonNode?[] options = []; byte[]? photo; string actionID = Guid.NewGuid().ToString("D"), mediaID = Guid.NewGuid().ToString("D"); bool busy;
    public KitchenCookingEditorPage(FamilyStore store, string? recipeID = null) {
        this.store = store; initial = recipeID; Title = "做菜打卡"; BackgroundColor = MomentStyle.Background; Content = new ScrollView { Content = body };
        body.Add(picker); body.Add(MomentStyle.Action("创建个人菜谱", () => _ = Navigation.PushAsync(new KitchenRecipeEditorPage(store))));
        body.Add(MomentStyle.Action("拍照 / 从相册选择成品", () => _ = KitchenPersonal.Run(this, async () => { var data = await KitchenPersonal.Photo(this); if (data != null) { photo = data; mediaID = Guid.NewGuid().ToString("D"); Reset(); image.Source = ImageSource.FromStream(() => new MemoryStream(data)); } })));
        body.Add(image); body.Add(day); body.Add(note); body.Add(MomentStyle.Action("完成打卡", () => _ = Save(), true));
        picker.SelectedIndexChanged += (_, _) => Reset(); day.DateSelected += (_, _) => Reset(); note.TextChanged += (_, _) => Reset();
    }
    void Reset() => actionID = Guid.NewGuid().ToString("D");
    protected override void OnAppearing() { base.OnAppearing(); _ = KitchenPersonal.Run(this, async () => { var selected = picker.SelectedIndex >= 0 && picker.SelectedIndex < options.Length ? KitchenPersonal.Text(options[picker.SelectedIndex], "id") : initial; var data = await KitchenPersonal.Get(store, "catalog"); options = KitchenPersonal.Array(data, "items").ToArray(); picker.ItemsSource = options.Select(x => KitchenPersonal.Text(x, "name")).ToArray(); picker.SelectedIndex = System.Array.FindIndex(options, x => string.Equals(KitchenPersonal.Text(x, "id"), selected, StringComparison.OrdinalIgnoreCase)); }); }
    async Task Save() { if (busy) return; busy = true; body.IsEnabled = false; await KitchenPersonal.Run(this, async () => {
        if (photo == null || picker.SelectedIndex < 0) throw new FamilyApiException("请选择菜谱并拍摄或选择成品照片。"); var recipe = options[picker.SelectedIndex];
        await KitchenPersonal.Upload(store, mediaID, "checkin", photo);
        await store.CallAsync("/api/kitchen/checkins/" + actionID, HttpMethod.Put, new { recipeId = KitchenPersonal.Text(recipe, "id"), kind = KitchenPersonal.Text(recipe, "kind"), cookedOn = (day.Date ?? DateTime.Today).ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture), mediaId = mediaID, note = note.Text ?? "" }); await Navigation.PopAsync();
    }); busy = false; body.IsEnabled = true; }
}
public sealed class KitchenCookingHistoryPage : ContentPage
{
    readonly FamilyStore store; readonly string? recipeID; readonly VerticalStackLayout body = new() { Padding = 20, Spacing = 14 };
    public KitchenCookingHistoryPage(FamilyStore store, string? recipeID = null) { this.store = store; this.recipeID = recipeID; Title = "做过的菜"; BackgroundColor = MomentStyle.Background; Content = new ScrollView { Content = body }; ToolbarItems.Add(new ToolbarItem("拍照打卡", null, () => _ = Navigation.PushAsync(new KitchenCookingEditorPage(store, recipeID)))); }
    protected override void OnAppearing() { base.OnAppearing(); _ = Load(); }
    async Task Load() => await KitchenPersonal.Run(this, async () => {
        var totals = await KitchenPersonal.Get(store, "cooked"); var history = await KitchenPersonal.Get(store, "checkins"); body.Clear();
        foreach (var item in KitchenPersonal.Array(totals, "items")) if (recipeID == null || string.Equals(recipeID, KitchenPersonal.Text(item, "recipeId"), StringComparison.OrdinalIgnoreCase)) body.Add(MomentStyle.Title(KitchenPersonal.Text(item, "name") + " · " + KitchenPersonal.Text(item, "madeCount") + " 次", 20));
        foreach (var row in KitchenPersonal.Array(history, "items")) {
            if (recipeID != null && !string.Equals(recipeID, KitchenPersonal.Text(row, "recipeId"), StringComparison.OrdinalIgnoreCase)) continue;
            var id = KitchenPersonal.Text(row, "id"); body.Add(MomentStyle.Title(KitchenPersonal.Text(row, "name"), 18)); body.Add(MomentStyle.Caption(KitchenPersonal.Text(row, "cookedOn"))); KitchenPersonal.Image(body, store, KitchenPersonal.Text(row, "mediaId")); body.Add(new Label { Text = KitchenPersonal.Text(row, "note") });
            body.Add(MomentStyle.Action("关联菜谱", () => _ = KitchenPersonal.Run(this, async () => { var choices = KitchenPersonal.Array(await KitchenPersonal.Get(store, "catalog"), "items").ToArray(); var names = choices.Select((x, i) => (i + 1) + ". " + KitchenPersonal.Text(x, "name")).ToArray(); var choice = await DisplayActionSheetAsync("关联已有菜谱", "取消", null, names); var at = System.Array.IndexOf(names, choice); if (at >= 0) { await store.CallAsync($"/api/kitchen/checkins/{id}/recipe", HttpMethod.Patch, new { recipeId = KitchenPersonal.Text(choices[at], "id"), kind = KitchenPersonal.Text(choices[at], "kind") }); await Load(); } })));
            body.Add(MomentStyle.Action("删除打卡", () => _ = KitchenPersonal.Run(this, async () => { if (await DisplayAlertAsync("删除打卡？", "制作次数将同步更新。", "删除", "取消")) { await store.CallAsync("/api/kitchen/checkins/" + id, HttpMethod.Delete); await Load(); } })));
        }
        if (body.Count == 0) body.Add(MomentStyle.Caption("还没有做菜打卡记录。"));
    });
}
