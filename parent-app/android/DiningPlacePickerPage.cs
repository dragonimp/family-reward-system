using System.Text.Json;

namespace LinkoFamily;

internal sealed class DiningPlacePickerPage : ContentPage
{
    private readonly FamilyStore store;
    private readonly bool restaurant;
    private readonly TaskCompletionSource<DiningPlace?> selection = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly Entry query = new() { MaxLength = 80, ReturnType = ReturnType.Search };
    private readonly VerticalStackLayout results = new() { Spacing = 8 };
    private readonly Label status = MomentStyle.Caption("");
    private bool busy;
    private bool closed;

    private DiningPlacePickerPage(FamilyStore store, bool restaurant)
    {
        this.store = store;
        this.restaurant = restaurant;
        Title = restaurant ? "选择餐厅" : "调整位置";
        query.Placeholder = restaurant ? "搜索餐厅名称或地址（可加城市）" : "搜索城市和详细地址";
        query.Completed += (_, _) => _ = Search();
        var rows = new VerticalStackLayout { Padding = 20, Spacing = 12 };
        rows.Add(query);
        rows.Add(MomentStyle.Action("搜索", () => _ = Search(), true));
        rows.Add(MomentStyle.Action(restaurant ? "查找当前位置附近餐厅" : "使用设备当前位置", () => _ = Search(true)));
        rows.Add(status);
        rows.Add(results);
        Content = new ScrollView { Content = rows };
    }

    public static async Task<DiningPlace?> OpenAsync(Page owner, FamilyStore store, bool restaurant)
    {
        var page = new DiningPlacePickerPage(store, restaurant);
        await owner.Navigation.PushAsync(page);
        if (restaurant) _ = page.Search(true);
        return await page.selection.Task;
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        if (!closed) selection.TrySetResult(null);
        closed = true;
    }

    private async Task Search(bool nearby = false)
    {
        if (busy || closed) return;
        var term = query.Text?.Trim() ?? "";
        if (!nearby && term.Length == 0) { status.Text = "请输入搜索内容。"; return; }
        busy = true;
        results.Clear();
        status.Text = nearby ? "正在定位…" : "正在搜索…";
        try
        {
            if (restaurant)
            {
                JsonElement response;
                if (nearby)
                {
                    var point = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(GeolocationAccuracy.Medium, TimeSpan.FromSeconds(15)));
                    if (point is null) throw new InvalidOperationException();
                    response = await store.CallAsync("/api/dining/nearby", HttpMethod.Post,
                        new { latitude = point.Latitude, longitude = point.Longitude, driving = false });
                }
                else response = await store.CallAsync("/api/dining/search", HttpMethod.Post, new { query = term });
                if (closed) return;
                foreach (var place in response.GetProperty("restaurants").Deserialize<List<DiningPlace>>(new JsonSerializerOptions(JsonSerializerDefaults.Web)) ?? [])
                    Add(place);
            }
            else
            {
                IEnumerable<Location> locations;
                if (nearby)
                {
                    var point = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(GeolocationAccuracy.Medium, TimeSpan.FromSeconds(15)));
                    locations = point is null ? [] : [point];
                }
                else locations = await Geocoding.Default.GetLocationsAsync(term) ?? [];
                foreach (var point in locations.Take(20))
                {
                    if (closed) return;
                    var name = nearby ? "设备当前位置" : term;
                    Placemark? address = null;
                    try { address = (await Geocoding.Default.GetPlacemarksAsync(point))?.FirstOrDefault(); }
                    catch (Exception) { /* The chosen coordinates remain usable without a reverse address. */ }
                    if (closed) return;
                    var label = string.Join(" ", new[] { address?.Locality, address?.SubLocality, address?.Thoroughfare, address?.SubThoroughfare }
                        .Where(value => !string.IsNullOrWhiteSpace(value)));
                    Add(new DiningPlace("manual:" + Guid.NewGuid().ToString("D"), name, label, point.Latitude, point.Longitude, "", "manual", null, null, 0));
                }
            }
            status.Text = results.Children.Count == 0 ? "没有找到地点，可加上城市或详细地址重试。" : "";
        }
        catch (Exception) { if (!closed) status.Text = nearby ? "无法定位，可以直接搜索。" : "搜索暂未完成，请换个关键词或重试。"; }
        finally { busy = false; }
    }

    private void Add(DiningPlace place)
    {
        var title = string.IsNullOrWhiteSpace(place.Address) ? place.Name : $"{place.Name} · {place.Address}";
        results.Add(MomentStyle.Action(title, async () =>
        {
            if (closed) return;
            closed = true;
            try { await Navigation.PopAsync(); }
            finally { selection.TrySetResult(place); }
        }));
    }
}
