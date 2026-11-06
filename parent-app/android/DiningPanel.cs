using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace LinkoFamily;

public sealed class DiningPanel : ContentView
{
    private readonly FamilyStore store;
    private readonly ContentPage owner;
    private readonly VerticalStackLayout body = new() { Spacing = 20, Padding = new Thickness(20, 18, 20, 30) };
    private readonly string file;
    private DiningArchive archive = new();
    private readonly JsonSerializerOptions json = new() { PropertyNameCaseInsensitive = true };
    private List<DiningPlace> candidates = [];
    private DiningPlace? result;
    private Guid? circleId;
    private string mood = "automatic";
    private string resultMood = "automatic";
    private bool busy, checkingIn, confirmed, readable = true;
    private bool Working => busy || checkingIn;
    private Guid resultOperation;
    private string? message;
    private CancellationTokenSource? operation;
    private int generation;
    private DateTimeOffset fetchedAt;
    private DiningMealPeriod? cachedMeal, resultMeal;
    private static readonly (string Id, string Title)[] Moods = [("automatic", "🎲 随便安排"), ("familiar", "❤️ 还是老样子"), ("fresh", "✨ 来点新鲜的"), ("budget", "💰 今天省点钱"), ("treat", "😋 今天吃点好的"), ("spicy", "🌶️ 想吃点刺激的")];
    public DiningPanel(FamilyStore store, ContentPage owner, string userId)
    {
        this.store = store; this.owner = owner;
        file = Path.Combine(FileSystem.AppDataDirectory, "dining-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(DiningAccount.Identity(userId)))) + ".json");
        if (userId.Length == 0) { readable = false; message = "用户身份尚未就绪，请重新登录后重试。"; }
        else try { if (File.Exists(file)) {
            var loaded = JsonSerializer.Deserialize<DiningArchive>(File.ReadAllText(file), json) ?? throw new InvalidDataException();
            if (loaded.History is null || loaded.Habits is null || loaded.Favorites is null || loaded.Circles is null || loaded.History.Any(c => c.Place is null)) throw new InvalidDataException();
            archive = loaded;
        } }
        catch { readable = false; message = "干饭记录暂时无法读取，原记录已保留，请重试。"; }
        Content = new ScrollView { Content = body }; Render();
    }
    public void Suspend() { ++generation; operation?.Cancel(); busy = false; checkingIn = false; Render(); }
    private bool Update(Action<DiningArchive> change)
    {
        if (!readable) { message = "干饭记录暂时无法读取，原记录已保留，请重试。"; return false; }
        try {
            var next = JsonSerializer.Deserialize<DiningArchive>(JsonSerializer.Serialize(archive), json)!;
            change(next);
            File.WriteAllText(file + ".tmp", JsonSerializer.Serialize(next));
            File.Move(file + ".tmp", file, true); archive = next; return true;
        } catch { message = "记录没有保存成功，请重试。原记录已保留。"; return false; }
    }
    private void Render()
    {
        body.Children.Clear();
        var header = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
        header.Add(MomentStyle.Title("干饭", 30));
        var menu = MomentStyle.Action("⋯", () => _ = Menu()); menu.IsEnabled = !Working;
        SemanticProperties.SetDescription(menu, "干饭菜单"); header.Add(menu, 1, 0); body.Add(header);
        body.Add(MomentStyle.Title("今天吃啥？", 32)); body.Add(MomentStyle.Caption("别纠结了，这顿我安排！"));
        body.Add(MomentStyle.Caption(archive.Circles.FirstOrDefault(c => c.Id == circleId)?.Name ?? "当前位置附近"));
        var hero = new VerticalStackLayout { Spacing = 16 };
        var rice = new Label { Text = "🍚", FontSize = 72, HorizontalTextAlignment = TextAlignment.Center };
        hero.Add(rice);
        if (busy) { hero.Add(new ActivityIndicator { IsRunning = true, Color = Colors.DarkOrange }); _ = rice.RotateToAsync(12, 250); }
        var decide = MomentStyle.Action(busy ? "正在安排这顿饭…" : "🎲 帮我决定", () => _ = Decide(), true); decide.IsEnabled = !Working; decide.BackgroundColor = Colors.DarkOrange; hero.Add(decide);
        hero.Add(MomentStyle.Caption("不选条件也可以，一键安排。")); if (result is null || busy) body.Add(MomentStyle.Card(hero));
        var moods = new HorizontalStackLayout { Spacing = 8 };
        foreach (var item in Moods) { var button = MomentStyle.Action(item.Title, () => { mood = item.Id; if (result != null) _ = Decide(); else Render(); }, mood == item.Id); button.IsEnabled = !Working; moods.Add(button); }
        body.Add(new ScrollView { Orientation = ScrollOrientation.Horizontal, Content = moods });
        var checkIn = MomentStyle.Action(checkingIn ? "正在查找附近餐厅…" : "到店打卡", () => _ = CheckInNearby());
        checkIn.IsEnabled = !Working;
        body.Add(checkIn);
        if (result is { } place)
        {
            var card = new VerticalStackLayout { Spacing = 14 };
            card.Add(MomentStyle.Title("命运安排好了，走，干饭！", 18)); card.Add(MomentStyle.Title(place.Name, 25));
            if (place.Address.Length > 0) card.Add(MomentStyle.Caption("📍 " + place.Address));
            card.Add(MomentStyle.Caption($"地图参考距离约 {place.DistanceMeters:0} 米 · 步行时间以导航为准"));
            var cuisine = place.Category.Split(';', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
                .LastOrDefault(type => type is not ("餐饮服务" or "餐饮相关场所" or "餐饮相关" or "中餐厅" or "外国餐厅" or "餐厅" or "中餐" or "西餐"));
            card.Add(MomentStyle.Caption(cuisine is null ? "暂无菜系或主打餐品信息。" : $"地图分类显示，这家店属于{cuisine}。"));
            card.Add(MomentStyle.Caption(place.Cost is > 0 ? $"人均约 ¥{place.Cost:0.##} · 高德地图参考价" : "人均消费暂无数据"));
            if (place.Rating is { } rating) card.Add(MomentStyle.Caption($"地图评分 {rating:0.#} / 5"));
            card.Add(new Label { Text = $"{MealTitle(resultMeal)} · {Reason(place)}", FontSize = 15 });
            var confirmationOperation = resultOperation;
            var confirm = MomentStyle.Action(confirmed ? "已选好，走，干饭！" : "✅ 就吃这家！", () =>
            {
                if (Working || confirmed || confirmationOperation != resultOperation || result?.Id != place.Id) return;
                confirmed = SaveCheckIn(place, resultMood, confirmationOperation);
                Render();
            }, true);
            confirm.IsEnabled = !confirmed && !Working;
            card.Add(confirm);
            var another = MomentStyle.Action("🎲 不行，再来一家！", () => _ = Decide()); another.IsEnabled = !Working; card.Add(another);
            card.Add(MomentStyle.Action("🗺️ 带我过去！", () => _ = Navigate(place)));
            card.Add(MomentStyle.Action(archive.Favorites.Any(p => p.Id == place.Id) ? "♥ 已收藏" : "♡ 收藏餐厅", () => { Update(a => { if (a.Favorites.Any(p => p.Id == place.Id)) a.Favorites.RemoveAll(p => p.Id == place.Id); else a.Favorites.Add(place); }); Render(); }));
            body.Add(MomentStyle.Card(card));
        }
        if (message is { Length: > 0 }) body.Add(new Label { Text = message, FontSize = 14, TextColor = Colors.DarkOrange });
        body.Add(MomentStyle.Caption("附近餐厅来自高德地图。位置仅用于本次搜索，习惯与记录保存在当前账号的本机空间。价格、评分缺失时不作推测。"));
    }
    private static string MealTitle(DiningMealPeriod? meal) => meal switch
    {
        DiningMealPeriod.Breakfast => "早餐推荐",
        DiningMealPeriod.Lunch => "午餐推荐",
        DiningMealPeriod.AfternoonTea => "下午茶推荐",
        _ => "晚餐推荐"
    };

    private string Reason(DiningPlace place)
    {
        var known = archive.Habits.GetValueOrDefault(place.Id)?.Visits > 0;
        return resultMood switch {
            "familiar" => known ? "这家店在你的干饭记录里，熟悉的味道值得再试。" : "还没有常吃记录，先从附近这家开始。",
            "fresh" => known ? "附近的新选择有限，熟悉的店也保留机会。" : "你的干饭记录里还没有这家，来点新鲜的！",
            "budget" or "treat" => place.Cost is > 0 ? "参考地图提供的人均价格挑选，实际消费以店家为准。" : "暂未获取可靠的人均价格，点单前记得向店家确认。",
            "spicy" => "按店名与菜系线索挑选，具体辣度请向店家确认。",
            _ => known ? "这家店在你的干饭记录里，熟悉的味道值得再试。" : "从附近真实餐厅中，为你挑了这一家。"
        };
    }
    private async Task Decide()
    {
        if (Working) return; busy = true; message = null; var current = ++generation;
        var meal = DiningMeal.Current(DateTimeOffset.Now);
        if (resultMeal != meal) { result = null; confirmed = false; }
        operation?.Cancel(); using var cancel = operation = new CancellationTokenSource(TimeSpan.FromSeconds(25)); Render();
        try {
            if (cachedMeal != meal || DateTimeOffset.UtcNow - fetchedAt > TimeSpan.FromMinutes(5)) candidates = [];
            if (candidates.Count == 0) {
                var saved = archive.Circles.FirstOrDefault(c => c.Id == circleId);
                var location = saved is null ? await Locate(cancel.Token) : new Location(saved.Latitude, saved.Longitude);
                var places = await NearbyPlaces(location, cancel.Token);
                if (current != generation) return;
                candidates = places.Where(place => DiningMeal.Includes(meal, place)).ToList();
                cachedMeal = meal;
                fetchedAt = DateTimeOffset.UtcNow;
            }
            await Task.Delay(450, cancel.Token);
            if (current != generation) return;
            if (DiningMeal.Current(DateTimeOffset.Now) != meal)
            {
                result = null;
                message = "餐段已切换，请重新推荐。";
                return;
            }
            var next = DiningRecommendation.Pick(candidates, mood, archive, result?.Id);
            if (next is null) { result = null; message = "附近暂时没有适合当前餐段的餐厅。试试其他生活圈，或稍后重新定位。"; return; }
            if (result is { } old && !confirmed) Update(a => a.Habit(old.Id).Skipped++);
            result = next; resultMood = mood; resultMeal = meal; confirmed = false; resultOperation = Guid.NewGuid();
            if (candidates.Count == 1) message = "附近暂时只找到这一家，可换个生活圈再试。";
        } catch (OperationCanceledException) { if (current == generation) message = "定位或搜索超时，请重试，或使用已保存的生活圈。"; }
        catch (PermissionException) { message = "请在系统设置中允许位置访问，或选择已保存的生活圈。"; }
        catch (Exception error) { if (current == generation) message = error is FamilyApiException ? error.Message : "附近餐厅暂时无法读取，请稍后重试。"; }
        finally { if (ReferenceEquals(operation, cancel)) operation = null; if (current == generation) { busy = false; Render(); } }
    }
    private bool SaveCheckIn(DiningPlace place, string? mood, Guid id, string? restaurantType = null)
    {
        if (!Update(a => a.CheckIn(place, mood, id, restaurantType))) return false;
        message = "打卡成功，已记入干饭记录。";
        return true;
    }

    private async Task CheckInNearby()
    {
        if (Working) return;
        checkingIn = true;
        message = null;
        var current = ++generation;
        var id = Guid.NewGuid();
        using var cancel = operation = new CancellationTokenSource(TimeSpan.FromSeconds(25));
        Render();
        try
        {
            var location = await Locate(cancel.Token);
            if (current != generation) return;
            if (location.Accuracy is > 500)
            {
                message = "定位精度不足，请开启精确位置后重试。";
                return;
            }

            var places = (await NearbyPlaces(location, cancel.Token))
                .Where(p => !string.IsNullOrWhiteSpace(p.Name) && p.DistanceMeters is >= 0 and <= 500)
                .OrderBy(p => p.DistanceMeters).DistinctBy(p => p.Id).ToList();
            if (current != generation) return;
            if (places.Count == 0)
            {
                message = "当前位置 500 米内未找到餐厅。";
                return;
            }

            var labels = places.Select((p, index) => $"{index + 1}. {p.Name} · 约 {p.DistanceMeters:0} 米"
                + (string.IsNullOrWhiteSpace(p.Address) ? "" : $" · {p.Address}")).ToArray();
            var choice = await owner.DisplayActionSheetAsync("请选择你所在的餐厅", "取消", null, labels);
            var index = Array.IndexOf(labels, choice);
            if (current != generation || index < 0) return;
            var place = places[index];
            while (current == generation)
            {
                var restaurantType = await owner.DisplayPromptAsync(place.Name, message ?? "餐厅类型（选填）",
                    accept: "确认打卡", cancel: "取消", placeholder: "餐厅类型（选填）", maxLength: 40);
                if (restaurantType is null || current != generation || SaveCheckIn(place, null, id, restaurantType)) break;
            }
        }
        catch (OperationCanceledException) { if (current == generation) message = "定位或搜索超时，请重试。"; }
        catch (PermissionException) { if (current == generation) message = "请在系统设置中允许位置访问后重试。"; }
        catch (Exception error) { if (current == generation) message = error is FamilyApiException ? error.Message : "无法读取附近餐厅，请检查定位权限或网络后重试。"; }
        finally
        {
            if (ReferenceEquals(operation, cancel)) operation = null;
            if (current == generation) { checkingIn = false; Render(); }
        }
    }

    private async Task<List<DiningPlace>> NearbyPlaces(Location location, CancellationToken ct)
    {
        var response = await store.CallAsync("/api/dining/nearby", HttpMethod.Post,
            new { latitude = location.Latitude, longitude = location.Longitude }, ct);
        return response.GetProperty("restaurants").Deserialize<List<DiningPlace>>(json) ?? throw new InvalidDataException();
    }
    private static async Task<Location> Locate(CancellationToken ct)
    {
        var value = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(GeolocationAccuracy.Medium, TimeSpan.FromSeconds(15)), ct);
        if (value is null || Math.Abs((DateTimeOffset.UtcNow - value.Timestamp).TotalMinutes) > 2) throw new InvalidOperationException();
        return value;
    }
    private async Task Navigate(DiningPlace place)
    {
        // GCJ-02 is passed to the provider that owns it; don't hand it to a WGS84 system navigator.
        var url = "https://uri.amap.com/navigation?to=" + FormattableString.Invariant($"{place.Longitude:F6},{place.Latitude:F6},") + Uri.EscapeDataString(place.Name) + "&mode=walk&coordinate=gaode&src=linkomoment&callnative=1";
        await AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri(url), BrowserLaunchMode.SystemPreferred);
    }
    private async Task Menu()
    {
        var choice = await owner.DisplayActionSheetAsync("干饭", "取消", null, "干饭记录与收藏", "我的生活圈", "重新定位");
        if (choice == "干饭记录与收藏") await Records();
        else if (choice == "我的生活圈") await Circles();
        else if (choice == "重新定位") { circleId = null; candidates = []; result = null; confirmed = false; Render(); }
    }
    private async Task Records()
    {
        var rows = new VerticalStackLayout { Spacing = 16, Padding = 20 };
        var page = new ContentPage { Title = "干饭记录与收藏", SafeAreaEdges = SafeAreaEdges.All, BackgroundColor = MomentStyle.Background, Content = new ScrollView { Content = rows } };
        void Fill() {
            rows.Children.Clear(); rows.Add(MomentStyle.Caption("记录与习惯仅保存在本机，切换账号相互隔离。")); rows.Add(MomentStyle.Title("我的收藏", 22));
            foreach (var place in archive.Favorites) rows.Add(MomentStyle.Card(MomentStyle.Row(place.Name, "导航", () => _ = Navigate(place))));
            if (archive.Favorites.Count == 0) rows.Add(MomentStyle.Caption("还没有收藏餐厅。"));
            rows.Add(MomentStyle.Title("干饭记录 · 当地时间", 22));
            foreach (var entry in archive.History) {
                var row = new VerticalStackLayout { Spacing = 8, Children = { MomentStyle.Title(entry.Place.Name, 18), MomentStyle.Caption(entry.SelectedAt.ToLocalTime().ToString("g")) } };
                if (entry.CheckedIn)
                {
                    row.Add(MomentStyle.Caption($"累计打卡 {archive.Habits.GetValueOrDefault(entry.Place.Id)?.CheckIns ?? 0} 次"));
                    if (entry.RestaurantType is { } type) row.Add(MomentStyle.Caption(type));
                }
                else row.Add(entry.EatenAt is not null ? MomentStyle.Caption("✓ 吃过了") : MomentStyle.Action("我吃过了", () => { Update(a => a.ConfirmEaten(entry.Id)); Fill(); }));
                rows.Add(MomentStyle.Card(row));
            }
            if (archive.History.Count == 0) rows.Add(MomentStyle.Caption("选好餐厅后，记录会保存在这里。"));
            if (message is not null) rows.Add(MomentStyle.Caption(message));
        }
        Fill(); await owner.Navigation.PushAsync(page);
    }
    private async Task Circles()
    {
        var labels = new[] { "当前位置", "🏠 将当前位置设为家", "🏢 将当前位置设为公司" }.Concat(archive.Circles.Select(c => c.Name)).ToArray();
        var choice = await owner.DisplayActionSheetAsync("我的生活圈", "取消", null, labels);
        if (choice is null or "取消") return;
        if (choice == "当前位置") circleId = null;
        else if (choice is "🏠 将当前位置设为家" or "🏢 将当前位置设为公司") {
            if (busy) return; busy = true; var current = ++generation; Render();
            using var cancel = operation = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            try {
                var location = await Locate(cancel.Token);
                if (current != generation) return;
                var name = choice.Contains("家") ? "家附近" : "公司附近"; var circle = new DiningCircle(Guid.NewGuid(), name, location.Latitude, location.Longitude);
                if (Update(a => { a.Circles.RemoveAll(c => c.Name == name); a.Circles.Add(circle); })) circleId = circle.Id;
            } catch { if (current == generation) message = "未能保存生活圈，请检查定位权限后重试。"; }
            finally { if (ReferenceEquals(operation, cancel)) operation = null; if (current == generation) busy = false; }
        } else circleId = archive.Circles.FirstOrDefault(c => c.Name == choice)?.Id;
        candidates = []; result = null; confirmed = false; Render();
    }
}
