using System.Text.Json;

namespace LinkoFamily;

public sealed class KitchenPanel : ContentView
{
    private readonly FamilyStore store;
    private readonly ContentPage owner;
    private readonly VerticalStackLayout body = new() { Padding = 20, Spacing = 16 };
    private JsonElement[] categories = [];
    private string? category;
    private JsonElement? recipe;
    private string? message;
    private bool busy;

    public KitchenPanel(FamilyStore store, ContentPage owner)
    {
        this.store = store;
        this.owner = owner;
        Content = new ScrollView { Content = body };
        Render();
    }

    public async Task Load()
    {
        if (busy || categories.Length > 0) return;
        busy = true; Render();
        try
        {
            var result = await store.CallAsync("/api/recipes/categories");
            categories = result.GetProperty("categories").EnumerateArray().ToArray();
            category = null;
            message = categories.Length == 0 ? "菜谱分类正在准备，请稍后再试。" : null;
        }
        catch { message = "菜谱暂时无法加载，请重试。"; }
        finally { busy = false; Render(); }
    }

    private async Task Choose()
    {
        if (busy || categories.Length == 0) return;
        busy = true; message = null; Render();
        var meal = DiningMeal.Current(DateTimeOffset.Now) switch
        {
            DiningMealPeriod.Breakfast => "breakfast",
            DiningMealPeriod.Lunch => "lunch",
            DiningMealPeriod.AfternoonTea => "afternoonTea",
            _ => "dinner"
        };
        var path = "/api/recipes/random?category=" + Uri.EscapeDataString(category == "all" ? "" : category ?? "") + "&meal=" + meal;
        if (recipe is { } old) path += "&exclude=" + Uri.EscapeDataString(Text(old, "recipeId"));
        try
        {
            var next = await store.CallAsync(path);
            if (next.GetProperty("ingredients").GetArrayLength() == 0 || next.GetProperty("steps").GetArrayLength() == 0)
                throw new InvalidDataException();
            recipe = next;
        }
        catch { message = "这个分类暂时没有可用菜谱，或网络连接失败。请重试。"; }
        finally { busy = false; Render(); }
    }

    private void Render()
    {
        body.Children.Clear();
        body.Add(MomentStyle.Title("今天做什么？", 28));
        var grid = new Grid { ColumnSpacing = 10, RowSpacing = 10,
            ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Star) } };
        for (var index = 0; index < categories.Length; index++)
        {
            var item = categories[index];
            var id = Text(item, "id");
            var selected = category == id;
            var button = new Button { Text = Text(item, "icon") + " " + Text(item, "name"), BackgroundColor = Colors.Transparent, TextColor = MomentStyle.Ink, BorderWidth = 0 };
            button.Clicked += (_, _) => { category = selected ? null : id; recipe = null; Render(); };
            var border = new Border
            {
                Content = button, Stroke = selected ? Colors.Gray : Colors.LightGray, StrokeThickness = 1,
                StrokeShape = new Microsoft.Maui.Controls.Shapes.RoundRectangle { CornerRadius = 14 },
                StrokeDashArray = selected ? new DoubleCollection() : new DoubleCollection { 5, 4 }
            };
            if (grid.RowDefinitions.Count <= index / 2) grid.RowDefinitions.Add(new RowDefinition(GridLength.Auto));
            grid.Add(border, index % 2, index / 2);
        }
        body.Add(grid);
        if (categories.Length > 0 && category is null) body.Add(MomentStyle.Caption("不选分类，随便做一道"));
        if (categories.Length == 0) body.Add(MomentStyle.Action("加载菜谱分类", () => _ = Load()));
        else body.Add(MomentStyle.Action("随机选一道", () => _ = Choose(), true));
        if (busy) body.Add(new ActivityIndicator { IsRunning = true });
        if (recipe is { } current)
        {
            body.Add(MomentStyle.Title(Text(current, "name"), 24));
            body.Add(MomentStyle.Caption(Meta(current)));
            body.Add(new Label { Text = Text(current, "description") });
            body.Add(MomentStyle.Action("查看做法", () => _ = Detail(current), true));
            body.Add(MomentStyle.Action("换一道", () => _ = Choose()));
        }
        if (message is not null) body.Add(MomentStyle.Caption(message));
        body.IsEnabled = !busy;
    }

    private async Task Detail(JsonElement current)
    {
        var rows = new VerticalStackLayout { Padding = 20, Spacing = 14 };
        rows.Add(MomentStyle.Title(Text(current, "name"), 26));
        Image(rows, Text(current, "coverImage"));
        rows.Add(MomentStyle.Caption(Meta(current)));
        rows.Add(new Label { Text = Text(current, "description") });
        rows.Add(MomentStyle.Title("食材", 21));
        foreach (var item in current.GetProperty("ingredients").EnumerateArray())
            rows.Add(new Label { Text = Text(item, "name") + " · " + item.GetProperty("quantity").ToString() + " " + Text(item, "unit") });
        rows.Add(MomentStyle.Title("准备工作", 21));
        foreach (var item in current.GetProperty("preparation").EnumerateArray()) rows.Add(new Label { Text = item.GetString() });
        rows.Add(MomentStyle.Title("制作步骤", 21));
        foreach (var step in current.GetProperty("steps").EnumerateArray())
        {
            rows.Add(MomentStyle.Title(step.GetProperty("number") + ". " + Text(step, "action"), 18));
            var url = Text(step, "illustrationUrl");
            Image(rows, url);
            rows.Add(new Label { Text = Text(step, "instruction") });
            if (url.Length == 0) rows.Add(MomentStyle.Caption("步骤插画暂未提供"));
        }
        rows.Add(MomentStyle.Title("注意事项", 21));
        foreach (var item in current.GetProperty("notes").EnumerateArray()) rows.Add(new Label { Text = item.GetString() });
        await owner.Navigation.PushAsync(new ContentPage { Title = "查看做法", SafeAreaEdges = SafeAreaEdges.All, Content = new ScrollView { Content = rows } });
    }

    private static string Text(JsonElement item, string name) =>
        item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
    private static string Meta(JsonElement item) =>
        item.GetProperty("duration") + " min · " + Text(item, "difficulty") + " · " + item.GetProperty("servings") + " 人份";
    private static void Image(VerticalStackLayout rows, string source)
    {
        if (Uri.TryCreate(source, UriKind.Absolute, out var url) && url.Scheme == "https")
            rows.Add(new Image { Source = new UriImageSource { Uri = url, CachingEnabled = true, CacheValidity = TimeSpan.FromDays(7) }, Aspect = Aspect.AspectFit, HeightRequest = 220 });
    }
}
