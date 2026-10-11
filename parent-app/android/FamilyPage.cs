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
    private string tab = "家庭";
    private int? childId;
    private string? note;

    public FamilyPage(FamilyStore store)
    {
        this.store = store;
        Title = "Linko Dear";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        var root = new Grid { RowDefinitions = new RowDefinitionCollection { new(GridLength.Auto), new(GridLength.Star) } };
        var scroll = new ScrollView { Content = content };
        root.Add(spinner, 0, 0);
        root.Add(scroll, 0, 1);
        Content = root;
        Render();
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        if (store.Authenticated || busy) return;
        await Run(store.RestoreAsync);
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
        content.Add(Heading("Linko Dear", 27));
        if (!store.Authenticated) { LoginContent(); return; }
        if (!store.ParentReady) { IdentityContent(); return; }
        if (childId is int id) { ChildContent(id); return; }
        var tabs = new HorizontalStackLayout { Spacing = 7 };
        foreach (var name in new[] { "家庭", "审批", "记录", "我的" })
        {
            var selected = name == tab;
            tabs.Add(Button(name, () => { tab = name; Render(); }, selected));
        }
        content.Add(new ScrollView { Content = tabs, Orientation = ScrollOrientation.Horizontal });
        switch (tab)
        {
            case "审批": ApprovalContent(); break;
            case "记录": LedgerContent(); break;
            case "我的": AccountContent(); break;
            default: FamilyContent(); break;
        }
    }

    private void LoginContent()
    {
        content.Add(Heading("陪孩子记录每一步成长", 21));
        content.Add(new Label { Text = "家庭、积分与成长记录和现有网页版共用数据。", TextColor = Colors.DimGray });
        content.Add(Button("用户中心登录", () => _ = BeginLogin(false), true));
        content.Add(Button("注册用户中心账号", () => _ = BeginLogin(true)));
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

    private void IdentityContent()
    {
        content.Add(Heading("选择家庭身份", 21));
        if (store.Profile?.Text("role") == "child")
            content.Add(new Label { Text = "当前账号是孩子身份。请使用家长账号登录。" });
        else if (store.Profile?.Bool("needsRole") == true)
            content.Add(Button("我是家长", () => _ = Run(store.SelectParentAsync), true));
        else content.Add(Button("重新读取", () => _ = Run(store.LoadAsync), true));
        content.Add(Button("退出登录", () => { store.Logout(); Render(); }));
    }

    private void FamilyContent()
    {
        content.Add(Heading("我的家庭", 21));
        var picker = new Picker { Title = "选择家庭" };
        foreach (var group in store.Groups) picker.Items.Add(group.Text("name"));
        picker.SelectedIndex = store.Groups.FindIndex(group => group.Id == store.GroupId);
        picker.SelectedIndexChanged += (_, _) =>
        {
            if (picker.SelectedIndex < 0) return;
            var id = store.Groups[picker.SelectedIndex].Id;
            if (id != store.GroupId) _ = Run(() => store.SelectGroupAsync(id));
        };
        content.Add(picker);
        content.Add(Button("创建家庭", () => _ = CreateFamily()));
        content.Add(Button("输入邀请码加入", () => _ = JoinFamily()));
        if (store.GroupId != 0) content.Add(Button("分享家庭邀请码", () => _ = ShareInvite()));
        content.Add(Heading($"孩子 · {store.Children.Count}", 21));
        foreach (var child in store.Children)
        {
            var row = new VerticalStackLayout { Spacing = 4 };
            row.Add(Heading(child.Text("name"), 18));
            row.Add(new Label { Text = $"{child.Number("score")} 积分 · ¥{child.Number("cash")} · {child.Number("items")} 件物品", TextColor = Colors.DimGray });
            row.Add(Button("查看与记录", () => { childId = child.Id; Render(); }, true));
            content.Add(Card(row));
        }
        if (store.Children.Count == 0) content.Add(new Label { Text = "还没有孩子。" });
        content.Add(Button("添加孩子", () => _ = AddChild()));
        content.Add(Button("刷新家庭数据", () => _ = Run(store.LoadAsync)));
    }

    private void ChildContent(int id)
    {
        var child = store.Children.FirstOrDefault(item => item.Id == id);
        if (child.Id == 0) { childId = null; Render(); return; }
        content.Add(Button("‹ 返回家庭", () => { childId = null; Render(); }));
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

    private void LedgerContent()
    {
        content.Add(Heading($"记录 · 共 {store.LedgerTotal} 条", 21));
        foreach (var row in store.Transactions)
        {
            var type = row.Text("type") == "cash" ? "元" : row.Text("type") == "item" ? "件" : "分";
            var box = new VerticalStackLayout { Spacing = 3 };
            box.Add(Heading($"{row.Text("childName")} · {row.Number("amount")} {type}", 17));
            box.Add(new Label { Text = row.Text("description") });
            box.Add(new Label { Text = $"{row.Text("date")} · {row.Text("category")}", TextColor = Colors.DimGray, FontSize = 12 });
            content.Add(Card(box));
        }
        if (store.Transactions.Count == 0) content.Add(new Label { Text = "还没有记录。" });
        if (store.Transactions.Count < store.LedgerTotal)
            content.Add(Button("加载更多", () => _ = Run(store.LoadMoreLedgerAsync)));
        content.Add(Button("刷新记录", () => _ = Run(store.LoadAsync)));
    }

    private void AccountContent()
    {
        content.Add(Heading("我的", 21));
        content.Add(new Label { Text = store.Profile?.Text("username") ?? "家长", FontSize = 18 });
        content.Add(new Label { Text = $"Android 首版 {AppInfo.Current.VersionString} · 数据与网页版共用" });
        content.Add(Button("刷新", () => _ = Run(store.LoadAsync)));
        content.Add(Button("退出登录", () => _ = Logout()));
    }

    private async Task Logout()
    {
        if (!await DisplayAlertAsync("退出登录", "清除本机登录凭据？", "退出", "取消")) return;
        store.Logout(); childId = null; tab = "家庭"; Render();
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
    { Text = text, FontSize = size, FontAttributes = FontAttributes.Bold, TextColor = Color.FromArgb("#16352F") };

    private static Button Button(string text, Action action, bool primary = false)
    {
        var button = new Button
        {
            Text = text, Padding = new Thickness(13, 8), CornerRadius = 12,
            BackgroundColor = Color.FromArgb(primary ? "#0F766E" : "#E2F1ED"),
            TextColor = Color.FromArgb(primary ? "#FFFFFF" : "#0F514B")
        };
        button.Clicked += (_, _) => action();
        return button;
    }

    private static Border Card(View child) => new()
    {
        Content = child, BackgroundColor = Colors.White, Padding = new Thickness(15),
        Stroke = Color.FromArgb("#D9E8E3"), StrokeShape = new Microsoft.Maui.Controls.Shapes.RoundRectangle { CornerRadius = 16 }
    };
}
