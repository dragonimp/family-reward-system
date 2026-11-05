using AgentIdentity.NativeClient;

namespace LinkoFamily;

// The application owns presentation; User Center's SDK owns inbox/auth contracts.
internal sealed class MomentInboxPage : ContentPage
{
    private readonly FamilyStore store;
    private readonly Action? openApprovals;
    private readonly VerticalStackLayout rows = new() { Padding = 16, Spacing = 12 };
    private readonly Label status = MomentStyle.Caption("");
    private NotificationClient? client;
    private CancellationTokenSource? loading;
    public MomentInboxPage(FamilyStore store, Action? openApprovals = null)
    {
        this.openApprovals = openApprovals;
        this.store = store; Title = "消息通知"; BackgroundColor = MomentStyle.Background; SafeAreaEdges = SafeAreaEdges.All;
        Content = new ScrollView { Content = rows };
        ToolbarItems.Add(new ToolbarItem("刷新", null, async () => await LoadAsync()));
    }
    protected override async void OnAppearing() { base.OnAppearing(); await LoadAsync(); }
    protected override void OnDisappearing() { loading?.Cancel(); base.OnDisappearing(); }
    private async Task LoadAsync()
    {
        loading?.Cancel(); var cancellation = loading = new CancellationTokenSource(); var session = store.SessionVersion;
        rows.Children.Clear();
        try { await store.RefreshRequestsAsync(); } catch (Exception) { }
        if (cancellation.IsCancellationRequested || session != store.SessionVersion) return;
        if (openApprovals != null) {
            var pending = store.Requests.Count(r => r.Text("status") == "pending");
            var approvals = MomentStyle.Action($"积分申请 · {pending} 条待处理", () => _ = OpenApprovalsAsync());
            rows.Add(MomentStyle.Card(approvals));
        }
        rows.Add(status); status.Text = "正在读取消息…";
        try
        {
            client ??= await store.NotificationsAsync(cancellation.Token);
            var inbox = await client.ListAsync(cancellation.Token);
            if (cancellation.IsCancellationRequested || session != store.SessionVersion) return;
            status.Text = $"请求与消息 · 未读 {inbox.UnreadCount}";
            foreach (var message in inbox.Items)
            {
                var stack = new VerticalStackLayout { Spacing = 7 };
                stack.Add(MomentStyle.Title((message.ReadAt == null ? "● " : "") + message.Title, 17));
                stack.Add(new Label { Text = message.Content, FontSize = 15, MaxLines = 3, LineBreakMode = LineBreakMode.TailTruncation });
                stack.Add(MomentStyle.Caption(LocalTime(message.CreatedAt)));
                var card = MomentStyle.Card(stack); var tap = new TapGestureRecognizer();
                tap.Tapped += async (_, _) => await OpenAsync(message); card.GestureRecognizers.Add(tap); rows.Add(card);
            }
            if (inbox.Items.Length == 0) rows.Add(MomentStyle.Caption("还没有消息。"));
        }
        catch (OperationCanceledException) { }
        catch { if (!cancellation.IsCancellationRequested) status.Text = "消息暂时无法读取，请刷新或重新登录后重试。"; }
        finally { if (loading == cancellation) loading = null; cancellation.Dispose(); }
    }
    private async Task OpenApprovalsAsync()
    {
        await Navigation.PopAsync();
        openApprovals?.Invoke();
    }
    private async Task OpenAsync(NotificationMessage message)
    {
        var body = new VerticalStackLayout { Padding = 16, Spacing = 14, Children = { MomentStyle.Title(message.Title, 22), new Label { Text = message.Content, FontSize = 16 }, MomentStyle.Caption(LocalTime(message.CreatedAt)) } };
        var detail = new ContentPage { Title = "消息详情", BackgroundColor = MomentStyle.Background, SafeAreaEdges = SafeAreaEdges.All, Content = new ScrollView { Content = body } };
        if (client != null) { try { await client.MarkReadAsync(message.Id); } catch { } }
        await Navigation.PushAsync(detail);
        if (message.SourceRecordId is not { } source || !source.StartsWith("photo-request:", StringComparison.Ordinal) || !Guid.TryParseExact(source["photo-request:".Length..], "D", out var request)) return;
        var session = store.SessionVersion;
        try
        {
            var data = new MomentRecord(await store.CallAsync($"/api/dear/social/photo-requests/{request:D}"));
            if (session != store.SessionVersion) return;
            var tenant = data.GuidValue("tenantId"); var activity = data.GuidValue("activityId");
            if (tenant == null || activity == null) return;
            var scope = new MomentScope(tenant.Value, activity.Value);
            body.Add(MomentStyle.Caption("请求人：" + data.Text("requesterDisplayName")));
            body.Add(MomentStyle.Caption(data.Flag("serverCached") ? "原文件已缓存，可在完整活动页继续接收。" : "原文件尚未缓存，需要保存原件的设备继续分享。"));
            if (data.Data.TryGetProperty("photo", out var photo) && photo.ValueKind == System.Text.Json.JsonValueKind.Object)
                body.Add(MomentStyle.Action("查看请求的照片", () => _ = Navigation.PushAsync(new MomentPhotoPage(store, new MomentThumbnails(store), new MomentFeedItem("photo", new MomentRecord(photo.Clone()), scope)))));
            body.Add(MomentStyle.Action("打开完整活动页处理请求", () => _ = MomentActivityPanel.OpenWebAsync(scope.Web), true));
        }
        catch { body.Add(MomentStyle.Caption("请求对象暂不可访问，请稍后重试。")); }
    }
    private static string LocalTime(DateTime value) => value.Kind == DateTimeKind.Unspecified ? "时间暂不可用" : value.ToLocalTime().ToString("g", System.Globalization.CultureInfo.CurrentCulture) + "（当地时间）";
}
