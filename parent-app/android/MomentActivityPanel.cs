using System.Text.Json;

namespace LinkoFamily;

// Native navigation and previews; existing authenticated activity APIs remain authoritative.
public sealed class MomentActivityPanel : ContentView
{
    private const string Api = "/api/dear/social/";
    private readonly FamilyStore store;
    private readonly Action<MomentScope, string> createExercise;
    private readonly Page owner;
    private readonly Action authenticationChanged;
    private readonly Grid layout = new() { RowDefinitions = new RowDefinitionCollection { new(GridLength.Auto), new(GridLength.Auto), new(GridLength.Star) }, Padding = new Thickness(16, 12, 16, 0), RowSpacing = 10 };
    private readonly ContentView header = new(), controls = new(), body = new();
    private readonly Label status = MomentStyle.Caption("");
    private readonly MomentThumbnails thumbnails;
    private List<MomentRecord> spaces = [], activities = [], joined = [];
    private Guid space;
    private MomentRecord? activity;
    private CancellationTokenSource? loading;
    private long session = -1;
    private int revision;
    private bool loaded, showJoined, needsRefresh;
    private string mode = "大图";
    private readonly MomentActivityLocations locations;
    private Switch? sharingToggle;
    private List<MomentFeedItem> feed = [];

    public MomentActivityPanel(FamilyStore store, Page owner, Action authenticationChanged, Action<MomentScope, string> createExercise)
    {
        this.createExercise = createExercise;
        locations = new MomentActivityLocations(store);
        locations.Status += text => MainThread.BeginInvokeOnMainThread(() => { status.Text = text; if (sharingToggle != null && !locations.Sharing) sharingToggle.IsToggled = false; });
        this.store = store; this.owner = owner; this.authenticationChanged = authenticationChanged;
        thumbnails = new MomentThumbnails(store);
        layout.Add(header, 0, 0); layout.Add(controls, 0, 1); layout.Add(body, 0, 2);
        Content = layout; RenderRoot();
    }
    public async Task ShowAsync()
    {
        if (session != store.SessionVersion) { Reset(); session = store.SessionVersion; }
        if (!loaded) await ReloadAsync();
        else if (needsRefresh) { if (activity is { } selected) await OpenActivityAsync(selected); else await ReloadAsync(); }
        else if (activity == null) RenderRoot();
    }
    public void Deactivate(bool stopLocation = true) { if (stopLocation) _ = locations.Stop(); if (loading != null) needsRefresh = true; revision++; loading?.Cancel(); loading?.Dispose(); loading = null; }
    public void Reset() { Deactivate(); loaded = false; spaces = []; activities = []; joined = []; activity = null; space = Guid.Empty; thumbnails.Clear(); body.Content = null; }
    public bool Back()
    {
        if (activity == null && !showJoined) return false;
        Deactivate(); activity = null; showJoined = false; RenderRoot(); return true;
    }
    private async Task RunAsync(Func<CancellationToken, Task> action)
    {
        Deactivate(stopLocation:false); var current = ++revision; var account = store.SessionVersion;
        var cancellation = loading = new CancellationTokenSource();
        status.Text = "正在异步加载…";
        try { await action(cancellation.Token); if (current == revision && Current(cancellation.Token)) needsRefresh = false; }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            if (current == revision && account == store.SessionVersion) status.Text = error.Message;
            if (!store.Authenticated) authenticationChanged();
        }
        finally { if (loading == cancellation) { loading = null; cancellation.Dispose(); } }
    }
    private bool Current(CancellationToken ct) => !ct.IsCancellationRequested && store.Authenticated && session == store.SessionVersion;
    private async Task ReloadAsync() => await RunAsync(async ct =>
    {
        var spacesTask = store.CallAsync(Api + "tenants", ct: ct);
        var joinedTask = store.CallAsync(Api + "activities/joined", ct: ct);
        await Task.WhenAll(spacesTask, joinedTask);
        var nextSpaces = MomentRecord.List(await spacesTask).Where(s => s.Text("role") is "owner" or "member").ToList();
        var nextJoined = MomentRecord.List(await joinedTask);
        if (!Current(ct)) return;
        spaces = nextSpaces; joined = nextJoined;
        if (!spaces.Any(s => s.Id == space)) space = spaces.FirstOrDefault().GuidValue("id") ?? Guid.Empty;
        activities = space == Guid.Empty
            ? []
            : MomentRecord.List(await store.CallAsync(Api + $"spaces/{space:D}/activities", ct: ct));
        if (!Current(ct)) return;
        loaded = true; status.Text = ""; RenderRoot();
    });
    private void RenderRoot()
    {
        activity = null;
        var title = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto), new(GridLength.Auto) } };
        if (showJoined) title.Add(new HorizontalStackLayout { Spacing = 6, Children = { MomentStyle.Action("‹", () => Back()), MomentStyle.Title("已参加的活动", 26) } });
        else title.Add(MomentStyle.Title("活动与分享"));
        title.Add(MomentStyle.Action("⋯", () => _ = RootMenuAsync()), 1, 0);
        title.Add(MomentStyle.IconButton("消息", "消息通知", () => _ = owner.Navigation.PushAsync(new MomentInboxPage(store))), 2, 0); header.Content = title;
        if (status.Parent is Layout previous) previous.Children.Remove(status);
        var stack = new VerticalStackLayout { Spacing = 10 };
        if (spaces.Count > 0 && !showJoined)
        {
            var picker = new Picker { Title = "我的空间", FontSize = 18, TextColor = MomentStyle.Accent };
            foreach (var row in spaces) picker.Items.Add(row.Text("name"));
            picker.SelectedIndex = spaces.FindIndex(s => s.Id == space);
            picker.SelectedIndexChanged += async (_, _) =>
            {
                if (picker.SelectedIndex < 0 || spaces[picker.SelectedIndex].Id == space) return;
                space = spaces[picker.SelectedIndex].Id; activities = []; RenderRoot();
                await RunAsync(async ct => { var rows = MomentRecord.List(await store.CallAsync(Api + $"spaces/{space:D}/activities", ct: ct)); if (Current(ct)) { activities = rows; status.Text = ""; RenderRoot(); } });
            };
            stack.Add(MomentStyle.Caption("我的空间")); stack.Add(MomentStyle.Card(picker));
        }
        var section = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
        section.Add(MomentStyle.Caption("活动列表"));
        if (space != Guid.Empty && !showJoined) section.Add(MomentStyle.Action("＋ 新增", () => _ = CreateActivityAsync()), 1, 0);
        stack.Add(section); stack.Add(MomentStyle.Caption("按活动日期排序 · 日期按设备当地时区显示")); stack.Add(status); controls.Content = stack;
        var visibleActivities = showJoined
            ? joined
            : activities.Concat(joined.Where(item => !activities.Any(current => current.Id == item.Id)));
        var items = visibleActivities
            .OrderByDescending(item => MomentDates.ActivityDate(item))
            .ThenBy(item => item.Id.ToString("D"), StringComparer.Ordinal)
            .ToList();
        var list = new CollectionView { ItemsSource = items, SelectionMode = SelectionMode.None, EmptyView = Empty("还没有活动", space == Guid.Empty ? "创建空间或在完整活动页接受邀请。" : "点击活动列表右侧的新增，记录一次相聚。"), ItemTemplate = new DataTemplate(() =>
        {
            var row = new ActivityRow();
            row.Opened += item => _ = OpenActivityAsync(item);
            return row;
        }) };
        body.Content = Refresh(list, () => _ = ReloadAsync());
    }
    private async Task RootMenuAsync()
    {
        var choice = await owner.DisplayActionSheetAsync("空间与活动", "取消", null, "已参加的活动", "创建空间", "刷新", "打开完整活动页");
        if (choice == "已参加的活动") { showJoined = true; RenderRoot(); }
        else if (choice == "创建空间")
        {
            var name = await owner.DisplayPromptAsync("创建空间", "例如：家人和朋友", "创建", "取消", maxLength: 200);
            if (string.IsNullOrWhiteSpace(name)) return;
            await RunAsync(async ct => { await store.CallAsync(Api + "tenants", HttpMethod.Post, new { name = name.Trim() }, ct); if (Current(ct)) { loaded = false; status.Text = "空间已创建，点击刷新查看。"; } });
            await ReloadAsync();
        }
        else if (choice == "刷新") await ReloadAsync();
        else if (choice == "打开完整活动页") await OpenWebAsync(new Uri("https://happylife.ai.impx.net/dear"));
    }
    private async Task CreateActivityAsync()
    {
        if (space == Guid.Empty) return;
        var target = space;
        var page = new MomentActivityEditor(async (title, description, day) =>
        {
            var account = store.SessionVersion;
            var response = await store.CallAsync(Api + $"tenants/{target:D}/activities", HttpMethod.Post, new { title, description, startsAt = MomentDates.StartOfDay(day) });
            if (account != store.SessionVersion) return;
            loaded = false;
            await ReloadAsync();
            await OpenActivityAsync(new MomentRecord(response));
        });
        await owner.Navigation.PushModalAsync(new NavigationPage(page) { BarBackgroundColor = MomentStyle.Background, BarTextColor = MomentStyle.Ink });
    }
    private async Task OpenActivityAsync(MomentRecord selected)
    {
        if (activity?.Id != selected.Id) await locations.Stop();
        activity = selected;
        var scope = new MomentScope(selected.Tenant(space), selected.Id);
        var top = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Auto), new(GridLength.Star), new(GridLength.Auto) } };
        top.Add(MomentStyle.Action("‹", () => Back()), 0, 0);
        top.Add(MomentStyle.Title(selected.Text("title"), 24), 1, 0);
        top.Add(MomentStyle.Action("⋯", () => _ = ActivityMenuAsync(scope, selected)), 2, 0); header.Content = top;
        if (status.Parent is Layout previous) previous.Children.Remove(status);
        var section = new VerticalStackLayout { Spacing = 12 };
        var summary = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
        summary.Add(MomentStyle.Caption("▦ " + MomentDates.ActivityLabel(selected)));
        var memberCount = MomentStyle.Caption("成员"); summary.Add(memberCount, 1); section.Add(MomentStyle.Card(summary));
        _ = LoadMembers();
        async Task LoadMembers() { try { var value = await store.CallAsync(scope.Api + "/members"); if (activity?.Id == selected.Id) memberCount.Text = value.GetArrayLength() + " 位成员"; } catch { } }
        var sharing = new VerticalStackLayout { Spacing = 4 };
        var shareRow = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
        shareRow.Add(new Label { Text = "共享我的位置", FontSize = 17, VerticalTextAlignment = TextAlignment.Center });
        sharingToggle = new Switch { IsToggled = locations.Sharing };
        sharingToggle.Toggled += async (_, e) => { if (e.Value && !locations.Sharing) await locations.Start(scope); else if (!e.Value && locations.Sharing) await locations.Stop(); };
        shareRow.Add(sharingToggle, 1); sharing.Add(shareRow); sharing.Add(MomentStyle.Divider());
        sharing.Add(MomentStyle.MenuRow("活动地图", "附近", () => _ = owner.Navigation.PushAsync(new MomentActivityMapPage(store, scope, selected.Text("title"))))); section.Add(MomentStyle.Card(sharing));
        section.Add(MomentStyle.Caption("照片分享"));
        var actions = new Grid { ColumnSpacing = 4 }; var names = new[] { "分享", "拍照", "拍视频", "打卡", "创建运动" };
        for (var i = 0; i < names.Length; i++) {
            actions.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star)); var action = names[i];
            var button = MomentStyle.Action(action, () => _ = ActivityAction(scope, selected, action)); button.MinimumWidthRequest = 0; button.FontSize = 12; button.Padding = new Thickness(3, 6); button.BackgroundColor = Color.FromArgb("#E2F6F7"); actions.Add(button, i);
        }
        var photos = new VerticalStackLayout { Spacing = 10 }; photos.Add(actions); photos.Add(MomentStyle.Divider());
        var modes = new[] { "大图", "紧凑", "网格 · 每行5张" };
        var modeHost = new ContentView();
        void Modes() { modeHost.Content = MomentStyle.Segmented(modes, Array.IndexOf(modes, mode), index => { mode = modes[index]; Modes(); RenderFeed(scope); }); }
        Modes(); photos.Add(modeHost); section.Add(MomentStyle.Card(photos)); section.Add(MomentStyle.Caption("活动动态 · 照片、打卡与日常")); section.Add(status);
        controls.Content = section;
        feed = []; RenderFeed(scope);
        await RunAsync(async ct =>
        {
            var photos = store.CallAsync(scope.Api + "/live/photos", ct: ct);
            var moments = store.CallAsync(scope.Api + "/moments", ct: ct);
            var checkins = store.CallAsync(scope.Api + "/checkins", ct: ct);
            await Task.WhenAll(photos, moments, checkins);
            var rows = MomentRecord.List(await photos).Select(p => new MomentFeedItem("photo", p, scope))
                .Concat(MomentRecord.List(await moments).Select(p => new MomentFeedItem("moment", p, scope)))
                .Concat(MomentRecord.List(await checkins).Select(p => new MomentFeedItem("checkin", p, scope)))
                .OrderByDescending(p => p.Record.Created).ToList();
            if (!Current(ct) || activity?.Id != selected.Id) return;
            feed = rows; status.Text = ""; RenderFeed(scope);
        });
    }
    private void RenderFeed(MomentScope scope)
    {
        var grid = mode == "网格 · 每行5张"; var expanded = mode == "大图";
        var items = (grid ? feed.Where(item => item.Kind == "photo") : feed).ToList();
        var list = new CollectionView { SelectionMode = SelectionMode.None, ItemsSource = items, EmptyView = Empty("还没有动态", "在右上角更多菜单中分享照片、写日常或打卡。"), ItemTemplate = new DataTemplate(() => new MomentFeedRow(store, owner, thumbnails, grid, scope, () => { if (activity is { } current) _ = OpenActivityAsync(current); }, feed.Where(p => p.Kind == "photo").ToList(), expanded)) };
        list.ItemsLayout = grid ? new GridItemsLayout(5, ItemsLayoutOrientation.Vertical) { HorizontalItemSpacing = 3, VerticalItemSpacing = 8 } : new LinearItemsLayout(ItemsLayoutOrientation.Vertical) { ItemSpacing = 10 };
        body.Content = Refresh(list, () => { if (activity is { } selected) _ = OpenActivityAsync(selected); });
    }
    private async Task ActivityAction(MomentScope scope, MomentRecord selected, string action)
    {
        if (action == "创建运动") createExercise(scope, selected.Text("title"));
        else if (action == "打卡") { await MomentActivityLocations.CheckIn(store, owner, scope); if (activity?.Id == selected.Id) await OpenActivityAsync(selected); }
        else {
            // Original-file sharing remains owned by the existing shared Moment web
            // component; do not introduce a second Android photo/transfer authority.
            var detail = action == "分享" ? "选择照片或视频并共享原文件" : action == "拍照" ? "拍摄照片后选择该照片共享" : "拍摄视频后选择该视频共享";
            if (await owner.DisplayAlertAsync(action, "在应用内完整活动页" + detail + "。", "继续", "取消")) await OpenWebAsync(scope.Web);
            needsRefresh = true;
        }
    }
    private async Task ActivityMenuAsync(MomentScope scope, MomentRecord selected)
    {
        var choice = await owner.DisplayActionSheetAsync("活动操作", "取消", null, "分享活动链接", "写日常", "在浏览器分享照片或打卡", "创建运动", "活动管理与邀请", "刷新");
        if (choice == "创建运动") createExercise(scope, selected.Text("title"));
        else if (choice == "分享活动链接") await Share.Default.RequestAsync(new ShareTextRequest { Title = selected.Text("title"), Uri = scope.ShareUrl.AbsoluteUri });
        else if (choice == "写日常")
        {
            var text = await owner.DisplayPromptAsync("写日常", "记录活动生活", "发表", "取消", maxLength: 2000);
            if (string.IsNullOrWhiteSpace(text)) return;
            await RunAsync(async ct => { await store.CallAsync(scope.Api + "/moments", HttpMethod.Post, new { text = text.Trim(), requestId = Guid.NewGuid() }, ct); });
            if (activity is { } current) await OpenActivityAsync(current);
        }
        else if (choice is "在浏览器分享照片或打卡" or "活动管理与邀请") await OpenWebAsync(scope.Web);
        else if (choice == "刷新") await OpenActivityAsync(selected);
    }
    internal static async Task OpenWebAsync(Uri url) => await AgentIdentity.Maui.InAppWebLinks.OpenAsync(url);
    private static View Empty(string title, string detail) => new VerticalStackLayout { Padding = new Thickness(20, 32), Spacing = 10, Children = { MomentStyle.Title(title, 20), MomentStyle.Caption(detail) } };
    private static RefreshView Refresh(CollectionView list, Action reload)
    {
        var refresh = new RefreshView { Content = list, RefreshColor = MomentStyle.Accent };
        refresh.Refreshing += (_, _) => { refresh.IsRefreshing = false; reload(); }; return refresh;
    }
    private sealed class ActivityRow : ContentView
    {
        private readonly Label title = MomentStyle.Title("", 18), date = MomentStyle.Caption("");
        public event Action<MomentRecord>? Opened;
        public ActivityRow()
        {
            var stack = new VerticalStackLayout { Spacing = 6 }; stack.Add(title); stack.Add(date);
            Content = MomentStyle.Card(stack); Margin = new Thickness(0, 0, 0, 10);
            var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => { if (BindingContext is MomentRecord item) Opened?.Invoke(item); }; GestureRecognizers.Add(tap);
        }
        protected override void OnBindingContextChanged() { base.OnBindingContextChanged(); if (BindingContext is MomentRecord item) { title.Text = item.Text("title"); date.Text = MomentDates.ActivityLabel(item); } }
    }
}

internal sealed class MomentActivityEditor : ContentPage
{
    public MomentActivityEditor(Func<string, string, DateTime, Task> save)
    {
        Title = "新增活动"; BackgroundColor = MomentStyle.Background; SafeAreaEdges = SafeAreaEdges.All;
        var name = new Entry { Placeholder = "活动名称，例如周末野餐", MaxLength = 200 };
        var description = new Editor { Placeholder = "活动介绍（可选）", MaxLength = 2000, AutoSize = EditorAutoSizeOption.TextChanges, MinimumHeightRequest = 100 };
        var date = new DatePicker { Date = DateTime.Today };
        var error = MomentStyle.Caption(""); error.TextColor = Colors.Red;
        var submit = MomentStyle.Action("创建活动", () => { }, true);
        submit.Clicked += async (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(name.Text)) { error.Text = "请填写活动名称。"; return; }
            submit.IsEnabled = false;
            try { await save(name.Text.Trim(), description.Text?.Trim() ?? "", date.GetValue(DatePicker.DateProperty) is DateTime day ? day : DateTime.Today); await Navigation.PopModalAsync(); }
            catch (Exception exception) { error.Text = exception.Message + "；请刷新列表核对后再重试。"; }
            finally { submit.IsEnabled = true; }
        };
        ToolbarItems.Add(new ToolbarItem("取消", null, async () => await Navigation.PopModalAsync()));
        Content = new ScrollView { Content = new VerticalStackLayout { Padding = 18, Spacing = 16, Children = { MomentStyle.Caption("活动信息"), MomentStyle.Card(new VerticalStackLayout { Spacing = 12, Children = { name, date, description } }), error, submit } } };
    }
}

internal sealed record MomentFeedItem(string Kind, MomentRecord Record, MomentScope Scope);
