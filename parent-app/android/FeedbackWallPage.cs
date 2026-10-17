using Microsoft.Maui.Controls.Shapes;

namespace LinkoFamily;

public sealed class FeedbackWallPage : ContentPage
{
    private readonly FamilyStore store;
    private readonly FeedbackWallClient client;
    private readonly Label summary = new() { FontSize = 13 };
    private readonly Label error = new() { FontSize = 14, IsVisible = false };
    private readonly VerticalStackLayout posts = new() { Spacing = 10 };
    private readonly Button wish = new() { Text = "心愿墙" };
    private readonly Button opinion = new() { Text = "意见墙" };
    private readonly Button mine = new() { Text = "我的反馈" };
    private readonly Button refresh = new() { Text = "刷新" };
    private readonly Button compose = new() { Text = "＋ 投稿" };
    private FeedbackWallSnapshot snapshot = new(0, 0, 0, 0, 0, []);
    private IReadOnlyList<FeedbackWallPost> myPosts = [];
    private CancellationTokenSource lifetime = new();
    private string category = "wish";
    private bool showingMine;
    private bool loading;
    private bool voting;

    public FeedbackWallPage(FamilyStore store)
    {
        this.store = store;
        client = new FeedbackWallClient(store.GetIdentityTokenAsync, () => !store.Authenticated,
            () => store.SessionVersion);
        Title = "用户反馈";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        summary.TextColor = Colors.DimGray;
        error.TextColor = Color.FromArgb("#B42335");

        wish.Clicked += (_, _) => { showingMine = false; category = "wish"; Render(); };
        opinion.Clicked += (_, _) => { showingMine = false; category = "opinion"; Render(); };
        mine.Clicked += async (_, _) =>
        {
            if (showingMine) { showingMine = false; await RefreshAsync(); return; }
            if (!store.Authenticated) { await DisplayAlertAsync("请先登录", "到“我的”登录后可查看已提交的反馈。", "好"); return; }
            showingMine = true; await RefreshAsync();
        };
        refresh.Clicked += async (_, _) => await RefreshAsync();
        compose.Clicked += async (_, _) =>
        {
            if (!store.Authenticated) { await DisplayAlertAsync("请先登录", "到“我的”登录后可提交反馈。", "好"); return; }
            await Navigation.PushAsync(new FeedbackComposePage(client, category));
        };

        var categories = new Grid { ColumnDefinitions = { new ColumnDefinition(GridLength.Star), new ColumnDefinition(GridLength.Star) }, ColumnSpacing = 8 };
        categories.Add(wish); Grid.SetColumn(opinion, 1); categories.Add(opinion);
        var actions = new Grid { ColumnDefinitions = { new ColumnDefinition(GridLength.Star), new ColumnDefinition(GridLength.Auto), new ColumnDefinition(GridLength.Auto) }, ColumnSpacing = 8 };
        actions.Add(mine); Grid.SetColumn(refresh, 1); actions.Add(refresh); Grid.SetColumn(compose, 2); actions.Add(compose);
        var body = new VerticalStackLayout { Padding = new Thickness(14, 8, 14, 28), Spacing = 10,
            Children = { categories, summary, actions, error, posts } };
        Content = new ScrollView { Content = body };
        Render();
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        lifetime = new CancellationTokenSource();
        await RefreshAsync();
    }

    protected override void OnDisappearing()
    {
        lifetime.Cancel();
        base.OnDisappearing();
    }

    private async Task RefreshAsync()
    {
        if (loading || voting) return;
        loading = true; refresh.IsEnabled = false; error.IsVisible = false; summary.Text = "正在读取反馈…";
        try
        {
            if (showingMine)
                myPosts = await client.MineAsync(lifetime.Token);
            else
                snapshot = await client.PublicAsync(lifetime.Token);
            Render();
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { error.Text = ex.Message; error.IsVisible = true; summary.Text = "加载失败"; }
        finally { loading = false; refresh.IsEnabled = true; }
    }

    private void Render()
    {
        Title = showingMine ? "我的反馈" : "用户反馈";
        wish.BackgroundColor = showingMine || category != "wish" ? Color.FromArgb("#E2F1ED") : Color.FromArgb("#0F766E");
        wish.TextColor = showingMine || category != "wish" ? Color.FromArgb("#0F514B") : Colors.White;
        opinion.BackgroundColor = showingMine || category != "opinion" ? Color.FromArgb("#E2F1ED") : Color.FromArgb("#0F766E");
        opinion.TextColor = showingMine || category != "opinion" ? Color.FromArgb("#0F514B") : Colors.White;
        mine.Text = showingMine ? "返回公开墙" : "我的反馈";
        if (showingMine)
        {
            summary.Text = $"我提交的反馈 · {myPosts.Count}";
        }
        else
        {
            summary.Text = $"已公开 {snapshot.Total} · 赞成 {snapshot.Upvotes} · 反对 {snapshot.Downvotes}";
        }
        posts.Children.Clear();
        var visible = showingMine ? myPosts : snapshot.Items.Where(post => post.Category == category).ToArray();
        if (!visible.Any()) posts.Add(Text(showingMine ? "还没有提交反馈。" : "还没有审核通过的提案。", "Muted"));
        foreach (var post in visible) posts.Add(PostCard(post));
    }

    private View PostCard(FeedbackWallPost post)
    {
        var content = new VerticalStackLayout { Spacing = 8 };
        content.Add(new Label { Text = post.Title, FontSize = 18, FontAttributes = FontAttributes.Bold });
        content.Add(new Label { Text = post.Content, FontSize = 15, LineBreakMode = LineBreakMode.WordWrap });
        if (showingMine)
        {
            content.Add(Text(post.ModerationStatus switch
            {
                "private" => "仅自己可见", "pending" => "申请公开 · 待审核",
                "approved" => "已公开", "rejected" => "公开申请未通过", _ => "处理中"
            }, "Muted"));
            if (!string.IsNullOrWhiteSpace(post.ReplyContent)) content.Add(Text("回复：" + post.ReplyContent, "Ink"));
        }
        else
        {
            var votes = new HorizontalStackLayout { Spacing = 8 };
            var up = new Button { Text = $"{(post.MyVote == 1 ? "▲" : "△")} {post.Upvotes}", FontSize = 14, IsEnabled = !post.IsMine && !voting };
            var down = new Button { Text = $"{(post.MyVote == -1 ? "▼" : "▽")} {post.Downvotes}", FontSize = 14, IsEnabled = !post.IsMine && !voting };
            up.Clicked += async (_, _) => await VoteAsync(post, post.MyVote == 1 ? 0 : 1);
            down.Clicked += async (_, _) => await VoteAsync(post, post.MyVote == -1 ? 0 : -1);
            votes.Add(up); votes.Add(down); votes.Add(Text($"净支持 {post.Score}", "Muted"));
            content.Add(votes);
        }
        var card = new Border { Padding = 14, StrokeThickness = 1, StrokeShape = new RoundRectangle { CornerRadius = 14 }, Content = content,
            BackgroundColor = Colors.White, Stroke = Color.FromArgb("#D9E8E3") };
        return card;
    }

    private async Task VoteAsync(FeedbackWallPost post, int value)
    {
        if (voting || loading) return;
        if (!store.Authenticated) { await DisplayAlertAsync("请先登录", "到“我的”登录后可为提案投票。", "好"); return; }
        voting = true;
        try { await client.VoteAsync(post.Id, value, lifetime.Token); }
        catch (OperationCanceledException) { return; }
        catch (Exception ex) { error.Text = ex.Message; error.IsVisible = true; return; }
        finally { voting = false; }
        await RefreshAsync();
    }

    private static Label Text(string value, string color)
    {
        var label = new Label { Text = value, FontSize = 13, VerticalTextAlignment = TextAlignment.Center };
        label.TextColor = color == "Ink" ? Color.FromArgb("#16352F") : Colors.DimGray;
        return label;
    }
}

public sealed class FeedbackComposePage : ContentPage
{
    private readonly FeedbackWallClient client;
    private readonly string category;
    private readonly Guid requestId = Guid.NewGuid();
    private readonly Entry title = new() { Placeholder = "简短标题", MaxLength = 200 };
    private readonly Editor content = new() { Placeholder = "反馈内容", AutoSize = EditorAutoSizeOption.TextChanges, MinimumHeightRequest = 150, MaxLength = 8000 };
    private readonly Switch requestedPublic = new();
    private readonly Label error = new() { FontSize = 14, IsVisible = false };
    private readonly Button submit = new() { Text = "提交", IsEnabled = false };
    private bool busy;

    public FeedbackComposePage(FeedbackWallClient client, string category)
    {
        this.client = client;
        this.category = category;
        Title = category == "wish" ? "写心愿" : "提意见";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        title.TextChanged += (_, _) => UpdateSubmit();
        content.TextChanged += (_, _) => UpdateSubmit();
        submit.BackgroundColor = Color.FromArgb("#0F766E");
        submit.TextColor = Colors.White;
        error.TextColor = Color.FromArgb("#B42335");
        submit.Clicked += async (_, _) => await SubmitAsync();
        var privacy = new Grid { ColumnDefinitions = { new ColumnDefinition(GridLength.Star), new ColumnDefinition(GridLength.Auto) } };
        privacy.Add(new Label { Text = "审核通过后公开展示", VerticalTextAlignment = TextAlignment.Center });
        Grid.SetColumn(requestedPublic, 1); privacy.Add(requestedPublic);
        var note = new Label { Text = "关闭时仅自己和管理员可见。开启后，审核通过才会出现在公开墙，其他用户可投票。", FontSize = 13 };
        note.TextColor = Colors.DimGray;
        var body = new VerticalStackLayout { Padding = new Thickness(18, 14, 18, 30), Spacing = 14,
            Children = { title, content, privacy, note, error, submit } };
        Content = new ScrollView { Content = body };
    }

    private void UpdateSubmit() => submit.IsEnabled = !busy && !string.IsNullOrWhiteSpace(title.Text) && !string.IsNullOrWhiteSpace(content.Text);

    private async Task SubmitAsync()
    {
        if (busy) return;
        busy = true; UpdateSubmit(); error.IsVisible = false;
        try
        {
            await client.CreateAsync(requestId, category, title.Text.Trim(), content.Text.Trim(), requestedPublic.IsToggled);
            await Navigation.PopAsync();
        }
        catch (Exception ex)
        {
            error.Text = ex.Message;
            error.IsVisible = true;
        }
        finally { busy = false; UpdateSubmit(); }
    }
}
