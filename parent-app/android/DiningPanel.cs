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
    private readonly ContentView modeHost = new();
    private DiningArchive archive = new();
    private DiningSyncState syncState = new();
    private readonly string syncFile, accountID;
    private bool syncing, syncAgain;
    private TaskCompletionSource? syncCompletion;
    private event Action? Synced;
    private string? syncMessage;
    private CancellationTokenSource? syncCancellation;
    private IDispatcherTimer? syncTimer;
    private static readonly JsonSerializerOptions SyncJson = new(JsonSerializerDefaults.Web);
    private static DiningArchive Copy(DiningArchive value) => JsonSerializer.Deserialize<DiningArchive>(JsonSerializer.Serialize(value, SyncJson), SyncJson)!;
    private static bool Same(DiningArchive? left, DiningArchive right) => left != null && System.Text.Json.Nodes.JsonNode.DeepEquals(JsonSerializer.SerializeToNode(left, SyncJson), JsonSerializer.SerializeToNode(right, SyncJson));
    private void WriteSync(DiningSyncState value)
    {
        File.WriteAllText(syncFile + ".tmp", JsonSerializer.Serialize(value, SyncJson));
        File.Move(syncFile + ".tmp", syncFile, true);
    }
    private bool OwnAccount(long session) => store.SessionVersion == session && store.Authenticated && DiningAccount.Identity(store.AccountProfile?.Subject ?? store.Profile?.Text("unifiedUserId") ?? "") == accountID;
    private async Task SyncAsync()
    {
        if (!readable) return;
        if (syncing) { syncAgain = true; if (syncCompletion != null) await syncCompletion.Task; return; }
        var session = store.SessionVersion; if (!OwnAccount(session)) return;
        syncing = true; syncCompletion = new TaskCompletionSource(); using var cancellation = syncCancellation = new CancellationTokenSource();
        try {
            do {
                syncAgain = false;
                if (syncState.Outbox == null && !Same(syncState.Baseline, archive)) {
                    syncState.Archive = archive;
                    syncState.Outbox = new DiningSyncRequest { Baseline = syncState.Baseline == null ? null : Copy(syncState.Baseline), Archive = Copy(archive) };
                    WriteSync(syncState); // Durable operation ID before any network mutation.
                }
                var sent = syncState.Outbox;
                if (sent != null) WriteSync(syncState);
                var snapshot = Copy(archive);
                var response = sent == null ? await store.CallAsync("/api/dining/account", ct: cancellation.Token)
                    : await store.CallAsync("/api/dining/account/sync", HttpMethod.Post, sent, cancellation.Token);
                if (!OwnAccount(session) || cancellation.IsCancellationRequested) return;
                var remote = response.GetProperty("archive").Deserialize<DiningArchive>(SyncJson) ?? throw new InvalidDataException();
                if (remote.History == null || remote.Habits == null || remote.Favorites == null || remote.Circles == null || remote.ManualRestaurants == null) throw new InvalidDataException();
                var unchanged = Same(sent?.Archive ?? snapshot, archive);
                var next = new DiningSyncState { Archive = unchanged ? remote : archive,
                    Baseline = unchanged ? Copy(remote) : sent?.Archive ?? syncState.Baseline };
                WriteSync(next); syncState = next; archive = next.Archive;
                syncAgain = !unchanged; syncMessage = null;
            } while (syncAgain && OwnAccount(session) && !cancellation.IsCancellationRequested);
        } catch (OperationCanceledException) { }
        catch (Exception error) { if (OwnAccount(session)) syncMessage = error is FamilyApiException ? error.Message + " 本机记录已保留。" : "干饭记录暂未同步；本机记录已保留，联网后自动重试。"; }
        finally { syncing = false; if (syncCancellation == cancellation) syncCancellation = null; syncCompletion?.TrySetResult(); if (OwnAccount(session)) { Render(); Synced?.Invoke(); } }
    }
    private readonly JsonSerializerOptions json = new() { PropertyNameCaseInsensitive = true };
    private List<DiningPlace> candidates = [];
    private DiningPlace? result;
    private Guid? circleId;
    private string mood = "automatic";
    private string selection = "recommended";
    private string resultMood = "automatic";
    private bool busy, checkingIn, confirmed, readable = true;
    private bool Working => busy || checkingIn;
    private Guid resultOperation;
    private string? message;
    private CancellationTokenSource? operation;
    private int generation;
    private DateTimeOffset fetchedAt;
    private DiningMealPeriod? cachedMeal, resultMeal;
    private DiningTrip trip;
    private DiningFood food;
    private DiningFood? cachedFood;
    private bool hasRequestedRecommendation;
    private bool cachedDriving;
    private JsonElement routeOrigin;
    private readonly Dictionary<string, double> routeTimes = new(StringComparer.Ordinal);
    private static readonly string[] TripTitles = ["不限路程", "走路 5 分钟内", "走路 10 分钟内", "开车 10 分钟内", "开车 20 分钟内", "2 公里内"];
    private static readonly string[] FoodTitles = ["智能推荐", "面食", "米饭", "火锅", "烧烤", "甜品饮品"];
    private static readonly (string Id, string Title)[] Moods = [("automatic", "🎲 随便安排"), ("familiar", "❤️ 还是老样子"), ("fresh", "✨ 来点新鲜的"), ("budget", "💰 今天省点钱"), ("treat", "😋 今天吃点好的"), ("spicy", "🌶️ 想吃点刺激的")];
    public DiningPanel(FamilyStore store, ContentPage owner, string userId)
    {
        this.store = store; this.owner = owner; accountID = DiningAccount.Identity(userId);
        file = Path.Combine(FileSystem.AppDataDirectory, "dining-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(DiningAccount.Identity(userId)))) + ".json");
        syncFile = file + ".sync-v1";
        if (userId.Length == 0) { readable = false; message = "用户身份尚未就绪，请重新登录后重试。"; }
        else try { if (File.Exists(syncFile)) {
            syncState = JsonSerializer.Deserialize<DiningSyncState>(File.ReadAllText(syncFile), SyncJson) ?? throw new InvalidDataException();
            archive = syncState.Archive;
            if (archive.History == null || archive.Habits == null || archive.Favorites == null || archive.Circles == null || archive.ManualRestaurants == null) throw new InvalidDataException();
        } else if (File.Exists(file)) {
            var loaded = JsonSerializer.Deserialize<DiningArchive>(File.ReadAllText(file), json) ?? throw new InvalidDataException();
            if (loaded.History is null || loaded.Habits is null || loaded.Favorites is null || loaded.Circles is null || loaded.ManualRestaurants is null || loaded.History.Any(c => c.Place is null)) throw new InvalidDataException();
            archive = loaded;
        } }
        catch { readable = false; message = "干饭记录暂时无法读取，原记录已保留，请重试。"; }
        var outside = new ScrollView { Content = body };
        var cooking = new KitchenPanel(store, owner);
        var viewport = new ContentView { Content = outside };
        Border Modes(int index) => MomentStyle.Segmented(new[] { "出去吃", "下厨房" }, index, next => {
            viewport.Content = next == 1 ? cooking : outside; modeHost.Content = Modes(next);
            if (next == 1) _ = cooking.Load();
        });
        var root = new Grid { RowDefinitions = new RowDefinitionCollection { new(GridLength.Auto), new(GridLength.Star) } };
        modeHost.Margin = new Thickness(16, 8); modeHost.Content = Modes(0); root.Add(modeHost); root.Add(viewport, 0, 1);
        Content = root;
        Loaded += (_, _) => {
            syncTimer ??= Dispatcher.CreateTimer(); syncTimer.Interval = TimeSpan.FromSeconds(30);
            if (!syncTimer.IsRunning) { syncTimer.Tick -= SyncTick; syncTimer.Tick += SyncTick; syncTimer.Start(); }
            _ = SyncAsync();
        };
        Unloaded += (_, _) => { syncTimer?.Stop(); };
        Render();
    }
    private void SyncTick(object? sender, EventArgs e) => _ = SyncAsync();
    public void Suspend() { syncTimer?.Stop(); syncCancellation?.Cancel(); ++generation; operation?.Cancel(); busy = false; checkingIn = false; Render(); }
    private bool Update(Action<DiningArchive> change)
    {
        if (!readable) { message = "干饭记录暂时无法读取，原记录已保留，请重试。"; return false; }
        try {
            var next = JsonSerializer.Deserialize<DiningArchive>(JsonSerializer.Serialize(archive), json)!;
            change(next);
            var nextState = new DiningSyncState { Archive = next, Baseline = syncState.Baseline, Outbox = syncState.Outbox };
            WriteSync(nextState); syncState = nextState; archive = next;
            _ = SyncAsync(); return true;
        } catch { message = "记录没有保存成功，请重试。原记录已保留。"; return false; }
    }
    private void Render()
    {
        body.Children.Clear();
        if (syncMessage != null) body.Add(MomentStyle.Caption(syncMessage));
        var header = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(44), new(GridLength.Star), new(44) } };
        var title = MomentStyle.Title("干饭", 19); title.HorizontalTextAlignment = TextAlignment.Center; title.VerticalTextAlignment = TextAlignment.Center; header.Add(title, 1);
        var menu = MomentStyle.IconButton("更多", "干饭菜单", () => _ = Menu()); menu.IsEnabled = !Working; header.Add(menu, 2); body.Add(header);
        var shortcuts = new Grid { ColumnSpacing = 4 };
        var items = new[] { ("推荐", "recommended", "automatic"), ("附近", "nearby", "automatic"), ("常去", "recommended", "familiar"), ("随机", "random", "automatic") };
        for (var i = 0; i < items.Length; i++) {
            shortcuts.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star)); var item = items[i];
            var active = selection == item.Item2 && (item.Item2 != "recommended" || (mood == "familiar") == (item.Item3 == "familiar"));
            var stack = new VerticalStackLayout { Spacing = 4, Padding = new Thickness(4, 7) }; stack.Add(MomentStyle.Icon(item.Item1, false));
            stack.Add(new Label { Text = item.Item1, FontSize = 14, FontAttributes = FontAttributes.Bold, HorizontalTextAlignment = TextAlignment.Center, TextColor = MomentStyle.Ink });
            var tile = MomentStyle.Card(stack, new Thickness(0)); tile.BackgroundColor = active ? Color.FromArgb("#FFF0E2") : Colors.Transparent; tile.IsEnabled = !Working;
            var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => { selection = item.Item2; mood = item.Item3; _ = Decide(); }; tile.GestureRecognizers.Add(tap); shortcuts.Add(tile, i);
        }
        body.Add(MomentStyle.Card(shortcuts, new Thickness(4)));
        var location = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
        var current = MomentStyle.Caption("◎ " + (archive.Circles.FirstOrDefault(c => c.Id == circleId)?.Name ?? "当前位置附近")); current.VerticalTextAlignment = TextAlignment.Center; location.Add(current);
        var filter = MomentStyle.Action("☷ 筛选", () => _ = Filters()); filter.IsEnabled = !Working; location.Add(filter, 1); body.Add(location);
        if (result is null || busy) {
            var hero = new VerticalStackLayout { Spacing = 16 }; hero.Add(MomentStyle.Bowl());
            var question = MomentStyle.Title("今天吃啥？", 28); question.HorizontalTextAlignment = TextAlignment.Center; hero.Add(question);
            if (busy) hero.Add(new ActivityIndicator { IsRunning = true, Color = Colors.DarkOrange });
            var decide = MomentStyle.Action(busy ? "正在安排这顿饭…" : "🎲 帮我决定", () => _ = Decide(), true); decide.IsEnabled = !Working; decide.BackgroundColor = Color.FromArgb("#FF8A20"); decide.CornerRadius = 28; hero.Add(decide);
            var card = MomentStyle.Card(hero, new Thickness(24)); card.BackgroundColor = Color.FromArgb("#F4E9E2"); body.Add(card);
        }
        if (result is { } place)
        {
            var card = new VerticalStackLayout { Spacing = 14 };
            card.Add(MomentStyle.Title("命运安排好了，走，干饭！", 18)); card.Add(MomentStyle.Title(place.Name, 25));
            if (place.Address.Length > 0) card.Add(MomentStyle.Caption("📍 " + place.Address));
            if (trip.HasTimeLimit() && routeTimes.TryGetValue(place.Id, out var seconds))
            {
                var transport = trip.Driving() ? "开车" : "步行";
                card.Add(MomentStyle.Caption($"预计{transport}约 {Math.Ceiling(seconds / 60):0} 分钟"));
            }
            else card.Add(MomentStyle.Caption($"地图参考距离约 {place.DistanceMeters:0} 米 · 步行时间以导航为准"));
            var cuisine = place.Category.Split(';', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
                .LastOrDefault(type => type is not ("餐饮服务" or "餐饮相关场所" or "餐饮相关" or "中餐厅" or "外国餐厅" or "餐厅" or "中餐" or "西餐"));
            card.Add(MomentStyle.Caption(cuisine is null ? "暂无菜系或主打餐品信息。" : $"地图分类显示，这家店属于{cuisine}。"));
            card.Add(MomentStyle.Caption(place.Cost is > 0 ? $"人均约 ¥{place.Cost:0.##} · 高德地图参考价" : "人均消费暂无数据"));
            if (place.Rating is { } rating) card.Add(MomentStyle.Caption($"地图评分 {rating:0.#} / 5"));
            card.Add(new Label { Text = $"{(resultMeal is null ? FoodTitles[(int)food] : MealTitle(resultMeal))} · {Reason(place)}", FontSize = 15 });
            var confirmationOperation = resultOperation;
            var confirm = MomentStyle.Action(confirmed ? "已选好，走，干饭！" : "就吃这家", () =>
            {
                if (Working || confirmed || confirmationOperation != resultOperation || result?.Id != place.Id) return;
                confirmed = SaveCheckIn(place, resultMood, confirmationOperation);
                Render();
            }, true);
            confirm.IsEnabled = !confirmed && !Working;
            card.Add(confirm);
            var travelActions = new Grid
            {
                ColumnSpacing = 6,
                ColumnDefinitions = new ColumnDefinitionCollection
                {
                    new(GridLength.Star), new(GridLength.Star), new(GridLength.Star)
                }
            };
            var another = RecommendationAction("换一家", () => _ = Decide());
            another.IsEnabled = !Working;
            travelActions.Add(another, 0, 0);
            var directions = RecommendationAction("带我去", () => _ = Navigate(place, trip.Driving()));
            directions.ImageSource = "dining_navigation_arrow";
            directions.ContentLayout = new Button.ButtonContentLayout(Button.ButtonContentLayout.ImagePosition.Left, 3);
            travelActions.Add(directions, 1, 0);
            travelActions.Add(RecommendationAction("点外卖", () => _ = OrderDelivery(place)), 2, 0);
            card.Add(travelActions);
            card.Add(MomentStyle.Action(archive.Favorites.Any(p => p.Id == place.Id) ? "♥ 已收藏" : "♡ 收藏餐厅", () => { Update(a => { if (a.Favorites.Any(p => p.Id == place.Id)) a.Favorites.RemoveAll(p => p.Id == place.Id); else a.Favorites.Add(place); }); Render(); }));
            body.Add(MomentStyle.Card(card));
        }
        if (message is { Length: > 0 }) body.Add(new Label { Text = message, FontSize = 14, TextColor = Colors.DarkOrange });
        body.Add(MomentStyle.Caption("附近餐厅来自高德地图。位置仅用于本次搜索，记录、收藏与偏好按账号跨设备同步。价格、评分缺失时不作推测。"));
    }
    private static Button RecommendationAction(string title, Action action)
    {
        var button = MomentStyle.Action(title, action);
        button.FontSize = 14;
        button.Padding = new Thickness(2, 8);
        return button;
    }

    private async Task OrderDelivery(DiningPlace place)
    {
        if (place.GetVerifiedMeituanShopUrl() is { } shop && TryOpenMeituan(shop)) return;
        var details = string.Join("\n", new[] { place.Name, place.Address,
            "请粘贴店名搜索，并按地址核对分店。是否配送以美团显示为准。" }.Where(text => !string.IsNullOrWhiteSpace(text)));
        if (!await owner.DisplayAlertAsync("点个外卖", details, "复制店名并打开美团外卖", "取消")) return;

        await Clipboard.Default.SetTextAsync(place.Name);
        if (TryOpenMeituan()) return;
        const string download = "前往官方下载";
        const string web = "打开美团外卖网页";
        var choice = await owner.DisplayActionSheetAsync("无法打开美团外卖，店名已复制", "取消", null, download, web);
        if (choice == download)
            await AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://waimai.meituan.com/mobile/download"));
        else if (choice == web)
            await AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://i.waimai.meituan.com/waimai/"));
    }

    private static bool TryOpenMeituan(Uri? shop = null)
    {
#if ANDROID
        var activity = Microsoft.Maui.ApplicationModel.Platform.CurrentActivity;
        if (activity?.PackageManager is not { } packageManager) return false;
        string[] packages = ["com.sankuai.meituan.takeoutnew", "com.sankuai.meituan"];
        foreach (var package in packages)
        {
            try
            {
                var intent = shop is null
                    ? packageManager.GetLaunchIntentForPackage(package)
                    : new Android.Content.Intent(Android.Content.Intent.ActionView, Android.Net.Uri.Parse(shop.AbsoluteUri))
                        .SetPackage(package);
                if (intent?.ResolveActivity(packageManager) is null) continue;
                activity.StartActivity(intent);
                return true;
            }
            catch (Android.Content.ActivityNotFoundException) { }
            catch (Java.Lang.SecurityException) { }
        }
#endif
        return false;
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
    private void RefreshRecommendationAfterFilterChange()
    {
        result = null; confirmed = false; message = null;
        if (hasRequestedRecommendation) _ = Decide();
        else Render();
    }

    private async Task Decide()
    {
        if (Working) return; busy = true; message = null; var current = ++generation;
        hasRequestedRecommendation = true;
        var meal = DiningMeal.Current(DateTimeOffset.Now);
        var mealKey = food == DiningFood.Smart ? meal : (DiningMealPeriod?)null;
        var driving = trip.Driving();
        if (resultMeal != mealKey) { result = null; confirmed = false; }
        operation?.Cancel(); using var cancel = operation = new CancellationTokenSource(TimeSpan.FromSeconds(25)); Render();
        try {
            if (cachedFood != food || cachedMeal != mealKey || cachedDriving != driving || DateTimeOffset.UtcNow - fetchedAt > TimeSpan.FromMinutes(5)) candidates = [];
            if (candidates.Count == 0) {
                var saved = archive.Circles.FirstOrDefault(c => c.Id == circleId);
                var location = saved is null ? await Locate(cancel.Token) : new Location(saved.Latitude, saved.Longitude);
                var response = await SearchNearby(location, driving, cancel.Token);
                if (current != generation) return;
                candidates = ReadPlaces(response).Where(place => food.Includes(place, meal)).ToList();
                routeOrigin = response.TryGetProperty("searchCenter", out var center) ? center : default;
                routeTimes.Clear();
                cachedDriving = driving;
                cachedFood = food;
                cachedMeal = mealKey;
                fetchedAt = DateTimeOffset.UtcNow;
            }
            var eligible = candidates.Where(place => trip.IncludesDistance(place.DistanceMeters)).ToList();
            if (trip.HasTimeLimit())
            {
                var nearest = eligible.OrderBy(p => p.DistanceMeters).DistinctBy(p => p.Id).Take(6).ToList();
                var missing = nearest.Where(p => !routeTimes.ContainsKey(p.Id)).ToList();
                if (missing.Count > 0)
                {
                    var times = await LookupRouteTimes(missing, driving, cancel.Token);
                    if (current != generation) return;
                    for (var i = 0; i < missing.Count; i++)
                        if (times[i] is > 0 and < double.PositiveInfinity) routeTimes[missing[i].Id] = times[i]!.Value;
                }
                eligible = nearest.Where(p => routeTimes.TryGetValue(p.Id, out var seconds) && trip.Includes(seconds)).ToList();
            }
            await Task.Delay(450, cancel.Token);
            if (current != generation) return;
            if (mealKey is not null && DiningMeal.Current(DateTimeOffset.Now) != meal)
            {
                result = null;
                message = "餐段已切换，请重新推荐。";
                return;
            }
            var next = DiningRecommendation.Pick(eligible, mood, archive, result?.Id, selection: selection);
            if (next is null)
            {
                result = null;
                message = trip != DiningTrip.Unrestricted && candidates.Count > 0
                    ? "暂未找到能确认符合路程上限的餐厅。可以放宽上限后重试。"
                    : food == DiningFood.Smart
                        ? "附近暂时没有适合当前餐段的餐厅。试试其他生活圈，或稍后重新定位。"
                        : "附近暂时没有符合所选食物类型的餐厅。";
                return;
            }
            if (result is { } old && !confirmed) Update(a => a.Habit(old.Id).Skipped++);
            result = next; resultMood = mood; resultMeal = mealKey; confirmed = false; resultOperation = Guid.NewGuid();
            if (eligible.Count == 1) message = "附近暂时只找到这一家，可换个生活圈再试。";
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
        using var cancel = operation = new CancellationTokenSource();
        Render();
        try
        {
            const string manual = "手动填写餐厅";
            const string nearby = "查找附近餐厅";
            var source = await owner.DisplayActionSheetAsync("到店打卡", "取消", null, nearby, manual);
            if (current != generation || source is not (manual or nearby)) return;
            if (source == manual)
            {
                await CheckInManual(current, id, cancel.Token);
                return;
            }
            cancel.CancelAfter(TimeSpan.FromSeconds(25));
            var location = await Locate(cancel.Token);
            if (current != generation) return;
            if (location.Accuracy is > 500)
            {
                message = "定位精度不足，请开启精确位置后重试。";
                return;
            }

            var places = ReadPlaces(await SearchNearby(location, false, cancel.Token))
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

    private async Task CheckInManual(int current, Guid id, CancellationToken ct)
    {
        var name = "";
        while (current == generation)
        {
            var input = await owner.DisplayPromptAsync("手动填写餐厅", "输入餐厅名称，再获取当前位置。",
                accept: "获取当前位置", cancel: "取消", initialValue: name, maxLength: 100);
            if (input is null || current != generation) return;
            name = input.Trim();
            if (name.Length != 0) break;
            await owner.DisplayAlertAsync("请填写餐厅名称", "填写后即可继续定位。", "好");
        }
        if (current != generation) return;
        var location = await Locate(ct, GeolocationAccuracy.Best);
        if (current != generation) return;
        var place = archive.ManualRestaurant(name, location.Latitude, location.Longitude);
        if (place is null)
        {
            message = "无法获取当前位置，请检查定位权限后重试。";
            return;
        }
        var resolvedAddress = await ResolveCheckInAddress(location, ct);
        if (current != generation) return;

        var address = new Entry { Placeholder = "地址（可修改）", Text = resolvedAddress, MaxLength = 200 };
        var type = new Entry { Placeholder = "餐厅类型（选填）", MaxLength = 40 };
        var status = MomentStyle.Caption("");
        var confirm = new Button { Text = "确认打卡" };
        var cancelButton = new Button { Text = "取消" };
        var form = new VerticalStackLayout { Padding = 20, Spacing = 12, Children =
        {
            MomentStyle.Title(place.Name, 24), MomentStyle.Caption("已获取当前位置"), address, type, status, confirm, cancelButton
        } };
        var page = new ContentPage { Title = "到店打卡", SafeAreaEdges = SafeAreaEdges.All, Content = new ScrollView { Content = form } };
        confirm.Clicked += async (_, _) =>
        {
            if (!confirm.IsEnabled) return;
            if (current != generation)
            {
                status.Text = "定位已失效，请返回后重新定位。";
                return;
            }
            confirm.IsEnabled = false;
            if (!SaveCheckIn(place with { Address = address.Text?.Trim() ?? "" }, null, id, type.Text))
            {
                status.Text = message;
                confirm.IsEnabled = true;
                return;
            }
            Render();
            await page.Navigation.PopModalAsync();
        };
        cancelButton.Clicked += async (_, _) => await page.Navigation.PopModalAsync();
        await owner.Navigation.PushModalAsync(page);
    }

    private static async Task<string> ResolveCheckInAddress(Location location, CancellationToken ct)
    {
        if (!global::Android.Locations.Geocoder.IsPresent) return "";
        try
        {
            var geocoder = new global::Android.Locations.Geocoder(global::Android.App.Application.Context,
                Java.Util.Locale.ForLanguageTag("zh-CN")!);
            var results = await geocoder.GetFromLocationAsync(location.Latitude, location.Longitude, 1)
                .WaitAsync(TimeSpan.FromSeconds(4), ct);
            return results?.FirstOrDefault()?.GetAddressLine(0) ?? "";
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is TimeoutException or Java.Lang.Exception or IOException) { return ""; }
    }

    private Task<JsonElement> SearchNearby(Location location, bool driving, CancellationToken ct) =>
        store.CallAsync("/api/dining/nearby", HttpMethod.Post,
            new { latitude = location.Latitude, longitude = location.Longitude, driving }, ct);

    private List<DiningPlace> ReadPlaces(JsonElement response) =>
        response.GetProperty("restaurants").Deserialize<List<DiningPlace>>(json) ?? throw new InvalidDataException();

    private async Task<double?[]> LookupRouteTimes(List<DiningPlace> places, bool driving, CancellationToken ct)
    {
        if (routeOrigin.ValueKind != JsonValueKind.Object) return new double?[places.Count];
        var response = await store.CallAsync("/api/dining/route-times", HttpMethod.Post, new
        {
            origin = routeOrigin,
            destinations = places.Select(p => new { latitude = p.Latitude, longitude = p.Longitude }).ToArray(),
            mode = driving ? "driving" : "walking"
        }, ct);
        var times = response.GetProperty("seconds").Deserialize<double?[]>(json);
        return times?.Length == places.Count ? times : throw new InvalidDataException();
    }
    private static async Task<Location> Locate(CancellationToken ct, GeolocationAccuracy accuracy = GeolocationAccuracy.Medium)
    {
        var value = await Geolocation.Default.GetLocationAsync(new GeolocationRequest(accuracy, TimeSpan.FromSeconds(15)), ct);
        if (value is null || Math.Abs((DateTimeOffset.UtcNow - value.Timestamp).TotalMinutes) > 2) throw new InvalidOperationException();
        return value;
    }
    private async Task Navigate(DiningPlace place, bool driving = false)
    {
        if (place.Provider != "amap")
        {
            await owner.DisplayAlertAsync("无法导航", "此目的地的坐标系尚未确认，请重新搜索餐厅。", "知道了");
            return;
        }
        var navigator = new ExternalMapNavigator(ExternalMapNavigator.ConfiguredTencentReferer);
        var available = navigator.GetAvailableMaps();
        var names = new[] { "高德地图", "腾讯地图" };
        var apps = new[] { MapApp.Amap, MapApp.Tencent };
        var labels = apps.Select((app, index) => names[index] + (available.Contains(app) ? "" : "（未安装或已停用）")).ToArray();
        var choice = await owner.DisplayActionSheetAsync("选择地图", "取消", null, labels);
        var selected = Array.IndexOf(labels, choice);
        if (selected < 0) return;
        if (!available.Contains(apps[selected]))
        {
            await owner.DisplayAlertAsync("请先安装地图", $"请在手机应用商店安装或启用{names[selected]}，然后返回重试。", "知道了");
            return;
        }
        var modes = new[] { "驾车", "步行", "公交", "骑行" };
        var travel = await owner.DisplayActionSheetAsync("导航方式", "取消", null, modes);
        var mode = Array.IndexOf(modes, travel);
        if (mode < 0) return;
        try
        {
            navigator.OpenNavigation(apps[selected], new MapDestination(place.Name, place.Latitude, place.Longitude, MapCoordinateSystem.Gcj02),
                new[] { NavigationMode.Driving, NavigationMode.Walking, NavigationMode.Transit, NavigationMode.Cycling }[mode]);
        }
        catch (Exception error) { await owner.DisplayAlertAsync("无法打开地图", error.Message, "知道了"); }
    }

    private async Task Filters()
    {
        var rows = new VerticalStackLayout { Padding = 20, Spacing = 14 };
        var page = new ContentPage { Title = "筛选", SafeAreaEdges = SafeAreaEdges.All, BackgroundColor = MomentStyle.Background, Content = rows };
        var foodChoice = new Picker { Title = "食物类型", ItemsSource = FoodTitles, SelectedIndex = (int)food };
        var tripChoice = new Picker { Title = "路程", ItemsSource = TripTitles, SelectedIndex = (int)trip };
        var moodChoice = new Picker { Title = "口味偏好", ItemsSource = Moods.Select(m => m.Title).ToArray(), SelectedIndex = Array.FindIndex(Moods, m => m.Id == mood) };
        rows.Add(MomentStyle.Caption("食物类型")); rows.Add(foodChoice); rows.Add(MomentStyle.Caption("路程")); rows.Add(tripChoice); rows.Add(MomentStyle.Caption("口味偏好")); rows.Add(moodChoice);
        page.ToolbarItems.Add(new ToolbarItem("完成", null, async () => {
            if (foodChoice.SelectedIndex < 0 || tripChoice.SelectedIndex < 0 || moodChoice.SelectedIndex < 0) return;
            var changed = food != (DiningFood)foodChoice.SelectedIndex || trip != (DiningTrip)tripChoice.SelectedIndex;
            if (trip.Driving() != ((DiningTrip)tripChoice.SelectedIndex).Driving()) routeTimes.Clear();
            food = (DiningFood)foodChoice.SelectedIndex; trip = (DiningTrip)tripChoice.SelectedIndex; mood = Moods[moodChoice.SelectedIndex].Id; selection = "recommended";
            await page.Navigation.PopModalAsync();
            if (changed) RefreshRecommendationAfterFilterChange(); else if (result != null) await Decide(); else Render();
        }));
        await owner.Navigation.PushModalAsync(new NavigationPage(page));
    }
    private async Task Menu()
    {
        var choice = await owner.DisplayActionSheetAsync("干饭", "取消", null, "到店打卡", "干饭记录与收藏", "我的生活圈", "重新定位");
        if (choice == "到店打卡") await CheckInNearby();
        else if (choice == "干饭记录与收藏") await Records();
        else if (choice == "我的生活圈") await Circles();
        else if (choice == "重新定位") { circleId = null; candidates = []; result = null; confirmed = false; Render(); }
    }
    private async Task Records()
    {
        var rows = new VerticalStackLayout { Spacing = 16, Padding = 20 };
        var page = new ContentPage { Title = "干饭记录与收藏", SafeAreaEdges = SafeAreaEdges.All, BackgroundColor = MomentStyle.Background, Content = new ScrollView { Content = rows } };
        void Fill() {
            rows.Children.Clear(); if (syncMessage != null) rows.Add(MomentStyle.Caption(syncMessage)); rows.Add(MomentStyle.Caption("记录、收藏与偏好按账号跨设备同步；离线修改联网后自动合并。")); rows.Add(MomentStyle.Title("我的收藏", 22));
            foreach (var place in archive.Favorites) rows.Add(MomentStyle.Card(MomentStyle.Row(place.Name, "导航", () => _ = Navigate(place))));
            if (archive.Favorites.Count == 0) rows.Add(MomentStyle.Caption("还没有收藏餐厅。"));
            rows.Add(MomentStyle.Title("干饭记录 · 当地时间", 22));
            foreach (var entry in archive.History) {
                var row = new VerticalStackLayout { Spacing = 8, Children = { MomentStyle.Title(entry.Place.Name, 18), MomentStyle.Caption(entry.SelectedAt.ToLocalTime().ToString("g")) } };
                if (entry.CheckedIn)
                {
                    row.Add(MomentStyle.Caption($"累计打卡 {archive.Habits.GetValueOrDefault(entry.Place.Id)?.CheckIns ?? 0} 次"));
                    if (entry.RestaurantType is { } type) row.Add(MomentStyle.Caption(type));
                    if (entry.Place.Provider == "manual")
                        row.Add(MomentStyle.Caption(entry.Place.Address.Length == 0 ? "已记录定位，暂无地址" : entry.Place.Address));
                }
                else row.Add(entry.EatenAt is not null ? MomentStyle.Caption("✓ 吃过了") : MomentStyle.Action("我吃过了", () => { Update(a => a.ConfirmEaten(entry.Id)); Fill(); }));
                rows.Add(MomentStyle.Card(row));
            }
            if (archive.History.Count == 0) rows.Add(MomentStyle.Caption("选好餐厅后，记录会保存在这里。"));
            if (message is not null) rows.Add(MomentStyle.Caption(message));
        }
        void RefreshRecords() => Fill();
        var recordsTimer = Dispatcher.CreateTimer(); recordsTimer.Interval = TimeSpan.FromSeconds(30);
        recordsTimer.Tick += (_, _) => _ = SyncAsync();
        page.Appearing += (_, _) => { Synced -= RefreshRecords; Synced += RefreshRecords; recordsTimer.Start(); _ = SyncAsync(); };
        page.Disappearing += (_, _) => { Synced -= RefreshRecords; recordsTimer.Stop(); };
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
