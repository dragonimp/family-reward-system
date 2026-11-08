using System.Globalization;
using System.Net;

namespace LinkoFamily;

public sealed class FamilyPage : ContentPage
{
    private readonly FamilyStore store;
    private readonly VerticalStackLayout content = new() { Spacing = 14, Padding = new Thickness(18, 18, 18, 30) };
    private readonly ActivityIndicator spinner = new() { IsVisible = false, Color = Color.FromArgb("#0F766E") };
    private CancellationTokenSource? loginCancellation;
    private bool busy;
    private string tab = "干饭";
    private readonly ContentView viewport = new();
    private readonly Grid bottom = new() { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Star), new(GridLength.Star), new(GridLength.Star), new(GridLength.Star) }, Padding = new Thickness(6, 8, 6, 12), BackgroundColor = Colors.White };
    private readonly ScrollView scroll;
    private MomentActivityPanel? activities;
    private int? childId;
    private string? note;
    private DiningPanel? dining;
    private string? diningUser;
    private ExercisePanel? exercise;
    private string? exerciseUser;

    public FamilyPage(FamilyStore store)
    {
        this.store = store;
        Title = "Linko Moment";
        BackgroundColor = MomentStyle.Background;
        SafeAreaEdges = SafeAreaEdges.All;
        NavigationPage.SetHasNavigationBar(this, false);
        var root = new Grid { RowDefinitions = new RowDefinitionCollection { new(GridLength.Auto), new(GridLength.Star), new(GridLength.Auto) } };
        scroll = new ScrollView { Content = content };
        viewport.Content = scroll;
        root.Add(spinner, 0, 0);
        root.Add(viewport, 0, 1);
        root.Add(bottom, 0, 2);
        Content = root;
        Render();
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        if (Window != null) { Window.Stopped -= WindowStopped; Window.Stopped += WindowStopped; }
        if (store.Authenticated) { if (tab == "活动" && activities != null) await activities.ShowAsync(); if (tab == "运动") exercise?.Show(); return; }
        if (busy) return;
        await Run(store.RestoreAsync);
    }

    private void WindowStopped(object? sender, EventArgs e) { exercise?.Suspend(); dining?.Suspend(); activities?.Deactivate(); }

    private static bool SectionEnabled(string name) => name == "我的" || Preferences.Default.Get("moment.sections." + name, name != "带娃");

    private void SectionSettings()
    {
        var rows = new VerticalStackLayout { Padding = 20, Spacing = 16 };
        foreach (var name in new[] { "干饭", "带娃", "活动", "运动" })
        {
            var toggle = new Switch { IsToggled = SectionEnabled(name) };
            toggle.Toggled += (_, e) => { Preferences.Default.Set("moment.sections." + name, e.Value); Render(); };
            var row = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
            row.Add(new Label { Text = name, VerticalOptions = LayoutOptions.Center }, 0, 0);
            row.Add(toggle, 1, 0); rows.Add(row);
        }
        _ = Navigation.PushAsync(new ContentPage { Title = "栏目启用", Content = rows, BackgroundColor = MomentStyle.Background });
    }

    private void SelectTab(string name)
    {
        if (name is "干饭" or "带娃" or "活动" or "运动") Preferences.Default.Set("moment.sections." + name, true);
        if (name != "干饭") dining?.Suspend();
        if (name != "运动") exercise?.Suspend();
        if (name != "活动") activities?.Deactivate();
        tab = name; childId = null; Render();
        Dispatcher.Dispatch(() => _ = scroll.ScrollToAsync(0, 0, false));
    }
    private void RenderNavigation()
    {
        bottom.Children.Clear();
        var selected = tab is "审批" or "记录" or "规则" or "管理" ? "带娃" : tab;
        var names = new[] { "干饭", "带娃", "活动", "运动", "我的" }.Where(SectionEnabled).ToArray();
        bottom.ColumnDefinitions.Clear();
        foreach (var _ in names) bottom.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        var column = 0;
        foreach (var name in names)
        {
            var active = selected == name;
            var view = new VerticalStackLayout { Spacing = 3, Padding = new Thickness(4, 3), MinimumHeightRequest = 52 };
            view.Add(MomentStyle.Icon(name, active));
            view.Add(new Label { Text = name, FontSize = 12, TextColor = active ? MomentStyle.Accent : Colors.Gray, HorizontalTextAlignment = TextAlignment.Center });
            var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => SelectTab(name); view.GestureRecognizers.Add(tap);
            SemanticProperties.SetDescription(view, name + (active ? "，已选中" : ""));
            bottom.Add(view, column++, 0);
        }
    }
    protected override bool OnBackButtonPressed()
    {
        if (childId != null) { childId = null; Render(); return true; }
        if (tab is "审批" or "记录" or "规则" or "管理") { SelectTab("带娃"); return true; }
        if (tab == "活动" && activities?.Back() == true) return true;
        return base.OnBackButtonPressed();
    }

    private async Task Run(Func<Task> action)
    {
        if (busy) return;
        busy = true; spinner.IsVisible = true; spinner.IsRunning = true;
        try { await action(); }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            await DisplayAlertAsync("操作未完成", error.Message, "知道了");
        }
        finally
        {
            busy = false; spinner.IsRunning = false; spinner.IsVisible = false; Render();
        }
    }

    private void Render()
    {
        content.Children.Clear();
        viewport.Content = scroll;
        bottom.IsVisible = store.Authenticated;
        if (bottom.IsVisible) RenderNavigation();
        if (!store.Authenticated) { dining?.Suspend(); dining = null; diningUser = null; activities?.Reset(); activities = null; exercise?.Suspend(); exercise = null; exerciseUser = null; LoginContent(); return; }
        if (!store.ParentReady && tab is not ("干饭" or "活动" or "我的")) { ParentProfileUnavailableContent(); return; }
        if (childId is int id) { ChildContent(id); return; }
        switch (tab)
        {
            case "干饭":
                var diningId = store.AccountProfile?.Subject ?? store.Profile?.Text("unifiedUserId") ?? "";
                if (dining == null || diningUser != diningId) { dining?.Suspend(); dining = new DiningPanel(store, this, diningId); diningUser = diningId; }
                viewport.Content = dining; break;
            case "活动":
                activities ??= new MomentActivityPanel(store, this, Render, (scope, title) => { SelectTab("运动"); exercise?.LinkActivity(scope, title); });
                viewport.Content = activities;
                _ = activities.ShowAsync(); break;
            case "管理": FamilyManagementContent(); break;
            case "审批":
                content.Add(Button("‹ 带娃", () => SelectTab("带娃")));
                ApprovalContent(); break;
            case "记录":
                content.Add(Button("‹ 带娃", () => SelectTab("带娃")));
                LedgerContent(); break;
            case "规则":
                content.Add(Button("‹ 带娃", () => SelectTab("带娃")));
                content.Add(Heading("奖励与行为规则", 28));
                foreach (var rule in store.Rules)
                    content.Add(Card(new VerticalStackLayout { Spacing = 6, Children = { Heading(rule.Text("name"), 18), MomentStyle.Caption($"{rule.Number("points")} 分 · {rule.Text("category")}") } }));
                if (store.Rules.Count == 0) content.Add(MomentStyle.Caption("还没有规则。"));
                break;
            case "运动":
                var user = store.Profile?.Text("unifiedUserId") ?? "";
                if (exercise == null || exerciseUser != user)
                {
                    exercise?.Suspend(); exercise = new ExercisePanel(user); exerciseUser = user;
                }
                content.Add(exercise); exercise.Show(); break;
            case "我的": AccountContent(); break;
            default: FamilyContent(); break;
        }
    }

    private void LoginContent()
    {
        content.Add(Heading("Linko Moment", 32));
        content.Add(Heading("陪孩子记录每一步成长", 23));
        content.Add(new Label { Text = "家庭、积分与成长记录和现有网页版共用数据。", TextColor = Colors.DimGray });
        content.Add(Button("用户中心登录", () => _ = BeginLogin(false), true));
        content.Add(Button("注册用户中心账号", () => _ = BeginLogin(true)));
        content.Add(Button("查看隐私政策", () => _ = Navigation.PushModalAsync(new PrivacyPolicyPage())));
        if (loginCancellation is not null)
        {
            content.Add(new Label { Text = store.DisplayCode is null ? "正在打开用户中心…" : $"本次登录验证码：{store.DisplayCode}" });
            content.Add(Button("取消登录", () => { store.CancelLogin(); loginCancellation?.Cancel(); loginCancellation = null; Render(); }));
        }
    }

    private async Task BeginLogin(bool register)
    {
        if (loginCancellation is not null) return;
        loginCancellation = new CancellationTokenSource();
        Render();
        try
        {
            await store.LoginAsync(register, _ => Render(), loginCancellation.Token);
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { await DisplayAlertAsync("登录未完成", error.Message, "知道了"); }
        finally { loginCancellation?.Dispose(); loginCancellation = null; Render(); }
    }

    private void ParentProfileUnavailableContent()
    {
        content.Add(Heading("家长资料暂时无法读取", 21));
        content.Add(Button("重新读取", () => _ = Run(store.LoadAsync), true));
        content.Add(Button("退出登录", () => { store.Logout(); Render(); }));
    }

    private void FamilyContent()
    {
        var header = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto), new(GridLength.Auto) }, ColumnSpacing = 8 };
        header.Add(Heading("带娃", 32));
        var menu = Button("⋯", () => _ = GrowthMenuAsync());
        SemanticProperties.SetDescription(menu, "成长管理菜单"); header.Add(menu, 1, 0);
        var pending = store.Requests.Count(r => r.Text("status") == "pending");
        var bell = new Grid();
        bell.Add(MomentStyle.IconButton("消息", $"积分申请与消息通知，{pending} 条申请待处理", () => _ = Navigation.PushAsync(new MomentInboxPage(store, () => SelectTab("审批")))));
        if (pending > 0) bell.Add(new Label { Text = pending > 99 ? "99+" : pending.ToString(), FontSize = 11, TextColor = Colors.White, BackgroundColor = Colors.Red, HorizontalOptions = LayoutOptions.End, VerticalOptions = LayoutOptions.Start, Padding = 3, InputTransparent = true });
        header.Add(bell, 2, 0);
        content.Add(header);
        content.Add(MomentStyle.Caption("我的孩子"));
        ChildCards(store.HomeChildren);
        if (store.HomeChildren.Count == 0) content.Add(MomentStyle.Caption("还没有孩子，可在右上角菜单添加。"));
        content.Add(MomentStyle.Caption("孩子成长总结"));
        foreach (var report in store.GrowthReports)
        {
            content.Add(Card(new VerticalStackLayout { Spacing = 8, Children = {
                Heading(report.Text("subjectName"), 18),
                MomentStyle.Caption(report.Text("periodStart") + " — " + report.Text("periodEnd")),
                new Label { Text = report.Text("praise") }, new Label { Text = report.Text("changeSummary") },
                MomentStyle.Caption(report.Text("nextStep")) } }));
        }
        if (store.GrowthReportError is { } error) content.Add(MomentStyle.Caption(error));
        else if (store.GrowthReports.Count == 0) content.Add(MomentStyle.Caption("暂无孩子成长报告。"));
        content.Add(MomentStyle.Caption("明细台账"));
        LedgerContent(preview: true);
    }

    private async Task GrowthMenuAsync()
    {
        var choice = await DisplayActionSheetAsync("成长管理", "取消", null, "家庭组与孩子管理", "奖励与行为规则", "亲子互动", "刷新成长数据");
        if (choice == "家庭组与孩子管理") SelectTab("管理");
        else if (choice == "奖励与行为规则") SelectTab("规则");
        else if (choice == "亲子互动") await AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://happylife.ai.impx.net/family-connections"), BrowserLaunchMode.SystemPreferred);
        else if (choice == "刷新成长数据") await Run(store.LoadAsync);
    }

    private void ChildCards(IEnumerable<FamilyRecord> children)
    {
        foreach (var child in children)
        {
            var name = child.Text("name");
            var avatar = new Border { WidthRequest = 48, HeightRequest = 48, BackgroundColor = MomentStyle.Accent.WithAlpha(0.12f), Stroke = Colors.Transparent,
                StrokeShape = new Microsoft.Maui.Controls.Shapes.RoundRectangle { CornerRadius = 14 }, Content = new Label { Text = string.IsNullOrEmpty(name) ? "孩" : StringInfo.GetNextTextElement(name), FontSize = 22, FontAttributes = FontAttributes.Bold, TextColor = MomentStyle.Accent, HorizontalTextAlignment = TextAlignment.Center, VerticalTextAlignment = TextAlignment.Center } };
            var info = new VerticalStackLayout { Spacing = 5 };
            info.Add(Heading(name, 18));
            info.Add(MomentStyle.Caption($"{child.Number("score")} 积分 · ¥{child.Number("cash")} · {child.Number("items")} 件物品"));
            info.Add(new Label { Text = "守约信用分：" + (child.Bool("creditUnavailable") ? "暂不可用" : child.Bool("creditEnabled") ? $"{child.Number("creditScore")} / 100" : "未开通"), FontSize = 14, TextColor = MomentStyle.Accent });
            var row = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Auto), new(GridLength.Star), new(GridLength.Auto) }, ColumnSpacing = 14, MinimumHeightRequest = 76 };
            row.Add(avatar); row.Add(info, 1, 0); row.Add(new Label { Text = "›", TextColor = Colors.Gray, FontSize = 24, VerticalTextAlignment = TextAlignment.Center }, 2, 0);
            var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => { _ = Run(async () => { if (child.Int("familyGroupId") != store.GroupId && store.Groups.Any(g => g.Id == child.Int("familyGroupId"))) await store.SelectGroupAsync(child.Int("familyGroupId")); childId = child.Id; }); }; row.GestureRecognizers.Add(tap);
            content.Add(Card(row));
        }
    }

    private void FamilyManagementContent()
    {
        content.Add(Button("‹ 带娃", () => SelectTab("带娃")));
        content.Add(Heading(store.Groups.FirstOrDefault(g => g.Id == store.GroupId).Text("name") is { Length: > 0 } familyName ? familyName : "带娃", 32));
        content.Add(Card(new VerticalStackLayout { Spacing = 8, Children = { Heading("一起照顾每一天", 22), MomentStyle.Caption("孩子成长、奖励审批和积分记录，都在这里。") } }));
        content.Add(MomentStyle.Caption("虚拟群组 · 一起成长"));
        var picker = new Picker { Title = "选择家庭" };
        foreach (var group in store.Groups) picker.Items.Add(group.Text("name"));
        picker.SelectedIndex = store.Groups.FindIndex(group => group.Id == store.GroupId);
        picker.SelectedIndexChanged += (_, _) =>
        {
            if (picker.SelectedIndex < 0) return;
            var id = store.Groups[picker.SelectedIndex].Id;
            if (id != store.GroupId) _ = Run(() => store.SelectGroupAsync(id));
        };
        var family = new VerticalStackLayout { Spacing = 4 };
        family.Add(picker);
        family.Add(Button("家庭管理与邀请 ⋯", () => _ = FamilyMenuAsync()));
        content.Add(Card(family));
        content.Add(MomentStyle.Caption($"孩子 · {store.Children.Count}"));
        ChildCards(store.Children);
        if (store.Children.Count == 0) content.Add(new Label { Text = "还没有孩子。" });
        content.Add(Button("添加孩子", () => _ = AddChild()));
        content.Add(MomentStyle.Caption("群组成长"));
        var growth = new VerticalStackLayout { Spacing = 0 };
        growth.Add(MomentStyle.Row("奖励与行为规则", action: () => SelectTab("规则"))); growth.Add(MomentStyle.Divider());
        growth.Add(MomentStyle.Row("成长足迹", "↗", () => _ = AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://happylife.ai.impx.net/growth"), BrowserLaunchMode.SystemPreferred))); growth.Add(MomentStyle.Divider());
        growth.Add(MomentStyle.Row("亲子互动", "↗", () => _ = AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://happylife.ai.impx.net/family-connections"), BrowserLaunchMode.SystemPreferred)));
        content.Add(Card(growth));
        if (store.GroupId != 0) { content.Add(MomentStyle.Caption("群组协作")); content.Add(Card(MomentStyle.Row("邀请组员", action: () => _ = ShareInvite()))); }
        content.Add(Button("刷新成长数据", () => _ = Run(store.LoadAsync)));
    }

    private void ChildContent(int id)
    {
        var child = store.Children.FirstOrDefault(item => item.Id == id);
        if (child.Id == 0) { childId = null; Render(); return; }
        content.Add(Button("‹ 返回成长", () => { childId = null; Render(); }));
        content.Add(Heading(child.Text("name"), 23));
        content.Add(Card(new Label { Text = $"积分 {child.Number("score")}  ·  零用钱 ¥{child.Number("cash")}  ·  物品 {child.Number("items")}", FontSize = 17 }));
        content.Add(Button("记录奖励或扣分", () => _ = AddReward(child), true));
        content.Add(Button("手表配对", () => _ = PairWatch(child)));
        content.Add(Button("生成孩子手表授权码", () => _ = GenerateWatchCode(child)));
        content.Add(Heading("奖励规则", 20));
        foreach (var rule in store.Rules.Take(30))
        {
            var label = $"{rule.Text("name")} · {rule.Number("points")} 分 · {rule.Text("category")}";
            content.Add(new Label { Text = label, FontSize = 15 });
        }
        content.Add(Button("刷新", () => _ = Run(store.LoadAsync)));
    }

    private void ApprovalContent()
    {
        content.Add(Heading("孩子的申请", 21));
        foreach (var request in store.Requests)
        {
            var box = new VerticalStackLayout { Spacing = 4 };
            box.Add(Heading($"{request.Text("childName")} · {request.Text("statusText")}", 17));
            box.Add(new Label { Text = $"{request.Text("title")} · {request.Number("points")} 积分" });
            if (!string.IsNullOrEmpty(request.Text("note"))) box.Add(new Label { Text = request.Text("note"), TextColor = Colors.DimGray });
            if (request.Text("status") == "pending") box.Add(Button("批准申请", () => _ = Approve(request), true));
            content.Add(Card(box));
        }
        if (store.Requests.Count == 0) content.Add(new Label { Text = "暂无申请。" });
        content.Add(Button("刷新申请", () => _ = Run(store.LoadAsync)));
    }

    private void LedgerContent(bool preview = false)
    {
        content.Add(Heading($"记录 · 共 {store.LedgerTotal} 条", 21));
        foreach (var row in preview ? store.Transactions.Take(5) : store.Transactions)
        {
            var type = row.Text("type") == "cash" ? "元" : row.Text("type") == "item" ? "件" : "分";
            var box = new VerticalStackLayout { Spacing = 3 };
            box.Add(Heading($"{row.Text("childName")} · {row.Number("amount")} {type}", 17));
            box.Add(new Label { Text = row.Text("description") });
            box.Add(new Label { Text = $"{row.Text("date")} · {row.Text("category")}", TextColor = Colors.DimGray, FontSize = 12 });
            content.Add(Card(box));
        }
        if (store.Transactions.Count == 0) content.Add(new Label { Text = "还没有记录。" });
        if (preview) { content.Add(Button("查看全部记录", () => SelectTab("记录"))); return; }
        if (store.Transactions.Count < store.LedgerTotal)
            content.Add(Button("加载更多", () => _ = Run(store.LoadMoreLedgerAsync)));
        content.Add(Button("刷新记录", () => _ = Run(store.LoadAsync)));
    }

    private void AccountContent()
    {
        content.Add(Heading("我的", 32));
        void Section(string title, params View[] rows)
        {
            content.Add(MomentStyle.Caption(title));
            var stack = new VerticalStackLayout { Spacing = 0 };
            foreach (var row in rows) { if (stack.Children.Count > 0) stack.Add(MomentStyle.Divider()); stack.Add(row); }
            content.Add(Card(stack));
        }
        Section("用户与权益",
            new AgentIdentity.Maui.UserCenterAccountRow {
                Username = store.AccountProfile?.Username ?? store.Profile?.Text("username") ?? "",
                DisplayName = store.AccountProfile?.DisplayName, IconEmoji = store.AccountProfile?.IconEmoji,
                ProfileCommand = new Command(async () => await AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://auth.ai.xmkurt.com/personal/info"), BrowserLaunchMode.SystemPreferred)),
                LogoutCommand = new Command(async () => await Logout()) },
            MomentStyle.Row("套餐权益", action: () => _ = Navigation.PushAsync(new SubscriptionBenefitsPage(store))),
            MomentStyle.Row("语言设置", action: () => _ = Navigation.PushAsync(new AgentIdentity.Maui.LanguageSettingsPage(new Uri("https://auth.ai.xmkurt.com"), "happylife.ai", store.GetIdentityTokenAsync))),
            MomentStyle.Row("消息中心", action: () => _ = Navigation.PushAsync(new MomentInboxPage(store))),
            MomentStyle.Row("修改密码", action: () => _ = AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://auth.ai.xmkurt.com/personal/info?section=password"), BrowserLaunchMode.SystemPreferred)));
        if (store.AccountProfileError is { } profileError) content.Add(new Label { Text = profileError, FontSize = 12 });
        Section("应用与设置", MomentStyle.Row("栏目启用", action: SectionSettings), MomentStyle.Row("家庭与成员", action: () => SelectTab("管理")), MomentStyle.Row("刷新资料", action: () => _ = Run(store.LoadAsync)));
        Section("帮助与隐私",
            MomentStyle.Row("隐私政策", action: () => _ = Navigation.PushModalAsync(new PrivacyPolicyPage())),
            MomentStyle.Row("用户协议", action: () => _ = Navigation.PushAsync(new AtlasInformationPage(false, "termsUrl"))),
            MomentStyle.Row("使用手册", action: () => _ = Navigation.PushAsync(new AtlasInformationPage(false, "userManualUrl"))),
            MomentStyle.Row("关于我们", AppInfo.Current.VersionString, () => _ = Navigation.PushAsync(new MomentAboutPage(store))),
            MomentStyle.Row("账号注销", action: () => _ = DeleteAccount()));

    }

    private async Task Logout()
    {
        if (!await DisplayAlertAsync("退出登录", "清除本机登录凭据？", "退出", "取消")) return;
        store.Logout(); activities?.Reset(); activities = null; childId = null; tab = "干饭"; Render();
    }

    private async Task DeleteAccount()
    {
        if (!await DisplayAlertAsync("前往用户中心注销账号？", "账号注销会影响同一用户中心账号使用的其他应用。用户中心还会要求进一步确认。", "继续注销", "取消")) return;
        await AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://auth.ai.xmkurt.com/personal/info?deleteAccount=1"), BrowserLaunchMode.SystemPreferred);
    }

    private async Task FamilyMenuAsync()
    {
        var choice = await DisplayActionSheetAsync("家庭管理与邀请", "取消", null, "创建家庭", "输入邀请码加入", "分享家庭邀请码");
        if (choice == "创建家庭") await CreateFamily();
        else if (choice == "输入邀请码加入") await JoinFamily();
        else if (choice == "分享家庭邀请码" && store.GroupId != 0) await ShareInvite();
    }

    private async Task CreateFamily()
    {
        var name = await Prompt("创建家庭", "家庭名称");
        if (name is null) return;
        await Mutate(() => store.CallAsync("/api/family-groups", HttpMethod.Post, new { name }));
    }

    private async Task JoinFamily()
    {
        var code = await Prompt("加入家庭", "8 位邀请码", Keyboard.Numeric);
        if (code is null) return;
        if (code.Length != 8 || !code.All(char.IsDigit)) { await DisplayAlertAsync("邀请码无效", "请输入 8 位数字邀请码。", "知道了"); return; }
        await Mutate(() => store.CallAsync("/api/family-groups/join", HttpMethod.Post, new { inviteCode = code }));
    }

    private async Task ShareInvite()
    {
        await Run(async () =>
        {
            var result = new FamilyRecord(await store.CallAsync($"/api/family-groups/{store.GroupId}/invite"));
            var url = result.Text("inviteUrl");
            if (!url.StartsWith("https://", StringComparison.Ordinal)) throw new FamilyApiException("服务未返回有效邀请链接。");
            await Share.Default.RequestAsync(new ShareTextRequest { Text = url, Title = "邀请加入家庭" });
        });
    }

    private async Task AddChild()
    {
        var name = await Prompt("添加孩子", "孩子姓名");
        if (name is null) return;
        object body = store.GroupId == 0
            ? new { name, note = "" }
            : new { name, note = "", familyGroupId = store.GroupId };
        await Mutate(() => store.CallAsync("/api/children", HttpMethod.Post, body));
    }

    private async Task AddReward(FamilyRecord child)
    {
        var kind = await DisplayActionSheetAsync("记录类型", "取消", null, "积分", "零用钱", "物品");
        if (kind is null or "取消") return;
        var direction = await DisplayActionSheetAsync("记录方向", "取消", null, "奖励", "扣除");
        if (direction is null or "取消") return;
        string item = "";
        decimal amount = 0;
        if (kind == "物品")
        {
            item = await Prompt("物品奖励", "物品名称") ?? "";
            if (item.Length == 0) return;
        }
        else
        {
            var raw = await Prompt("数量", "请输入大于零的数量", Keyboard.Numeric);
            if (raw is null) return;
            if (!decimal.TryParse(raw, NumberStyles.Number, CultureInfo.InvariantCulture, out amount) || amount <= 0)
            { await DisplayAlertAsync("数量无效", "请输入大于零的数量。", "知道了"); return; }
        }
        var description = await Prompt("记录内容", "例如：完成作业");
        if (description is null) return;
        var category = await Prompt("类别", "例如：日常");
        if (category is null) return;
        var type = kind == "积分" ? "points" : kind == "零用钱" ? "cash" : "items";
        var key = Guid.NewGuid().ToString();
        var date = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, TimeZoneInfo.FindSystemTimeZoneById("Asia/Shanghai")).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var body = new Dictionary<string, object>
        {
            ["child_id"] = child.Id, ["type"] = type, ["direction"] = direction == "奖励" ? "+" : "-",
            ["points"] = type == "points" ? amount : 0, ["cash_cny"] = type == "cash" ? amount : 0,
            ["items"] = item, ["description"] = description, ["category"] = category,
            ["date"] = date, ["idempotency_key"] = key
        };
        var rewardText = kind == "物品" ? item : amount.ToString(CultureInfo.InvariantCulture);
        if (!await DisplayAlertAsync("确认记录", $"{child.Text("name")} · {direction}{kind} {rewardText}\n{description}", "提交", "取消")) return;
        await Mutate(() => store.CallAsync("/api/transactions", HttpMethod.Post, body), uncertainWrite: true);
    }

    private async Task Approve(FamilyRecord request)
    {
        var note = await DisplayPromptAsync("批准申请", "给孩子的话（可留空）", "继续", "取消", maxLength: 200);
        if (note is null) return;
        if (!await DisplayAlertAsync("确认批准", $"批准 {request.Text("childName")} 的申请？", "批准", "取消")) return;
        await Mutate(() => store.CallAsync($"/api/reward-requests/{request.Id}/approve", HttpMethod.Post,
            new { familyGroupId = request.Int("familyGroupId"), reviewNote = note }), uncertainWrite: true);
    }

    private async Task PairWatch(FamilyRecord child)
    {
        var raw = await Prompt("连接手表", "输入手表显示的 8 位配对码");
        if (raw is null) return;
        var code = raw.Replace("-", "", StringComparison.Ordinal).ToUpperInvariant();
        if (code.Length != 8 || code.Any(ch => !"ABCDEFGHJKLMNPQRSTUVWXYZ23456789".Contains(ch)))
        { await DisplayAlertAsync("配对码无效", "请输入手表显示的 8 位设备码。", "知道了"); return; }
        if (!await DisplayAlertAsync("确认配对", $"将手表连接到 {child.Text("name")}？", "连接", "取消")) return;
        await Mutate(() => store.CallAsync($"/api/children/{child.Id}/pair-device", HttpMethod.Post, new { code }), uncertainWrite: true);
    }

    private async Task GenerateWatchCode(FamilyRecord child)
    {
        if (!await DisplayAlertAsync("生成授权码", $"为 {child.Text("name")} 生成 10 分钟有效的手表授权码？", "生成", "取消")) return;
        await Run(async () =>
        {
            var result = new FamilyRecord(await store.CallAsync($"/api/children/{child.Id}/auth-code", HttpMethod.Post,
                new { familyGroupId = store.GroupId, expiresInMinutes = 10 }));
            await DisplayAlertAsync("孩子手表授权码", $"{result.Text("code")}\n有效期至 {result.Text("expiresAt")}", "知道了");
        });
    }

    private async Task Mutate(Func<Task<System.Text.Json.JsonElement>> mutation, bool uncertainWrite = false)
    {
        await Run(async () =>
        {
            try { await mutation(); }
            catch (Exception error) when (uncertainWrite && error is HttpRequestException or TaskCanceledException)
            {
                throw new FamilyApiException("提交结果暂不明确。请先刷新记录或申请状态，再决定是否重试。");
            }
            try { await store.LoadAsync(); note = "已保存，数据已从服务端刷新。"; }
            catch (Exception error) { note = $"已提交成功，但刷新失败：{error.Message}。请稍后手动刷新。"; }
        });
        if (note is not null) { await DisplayAlertAsync("完成", note, "知道了"); note = null; }
    }

    private async Task<string?> Prompt(string title, string placeholder, Keyboard? keyboard = null)
    {
        var value = await DisplayPromptAsync(title, placeholder, "继续", "取消", keyboard: keyboard ?? Keyboard.Text, maxLength: 120);
        value = value?.Trim();
        if (value is not null && value.Length == 0) { await DisplayAlertAsync("内容为空", "请填写内容。", "知道了"); return null; }
        return value;
    }

    private static Label Heading(string text, double size) => new()
    { Text = text, FontSize = size, FontAttributes = FontAttributes.Bold, TextColor = MomentStyle.Ink };

    private static Button Button(string text, Action action, bool primary = false) => MomentStyle.Action(text, action, primary);
    private static Border Card(View child) => MomentStyle.Card(child);
}
