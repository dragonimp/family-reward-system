namespace LinkoFamily;

public sealed class SubscriptionBenefitsPage : ContentPage
{
    private readonly FamilyStore store;
    private readonly VerticalStackLayout body = new() { Spacing = 12, Padding = new Thickness(18, 18, 18, 24) };
    private bool loading;

    public SubscriptionBenefitsPage(FamilyStore store)
    {
        this.store = store;
        Title = "套餐权益";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        Content = new ScrollView { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Never };
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await LoadAsync();
    }

    private async Task LoadAsync()
    {
        if (loading) return;
        loading = true;
        body.Children.Clear();
        body.Children.Add(new ActivityIndicator { IsRunning = true, HorizontalOptions = LayoutOptions.Center });
        try
        {
            var snapshot = new FamilyRecord(await store.CallAsync("/api/subscription"));
            body.Children.Clear();
            body.Children.Add(new Label { Text = "当前权益", FontSize = 18, FontAttributes = FontAttributes.Bold });
            var current = snapshot.Get("subscription");
            if (current.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                var subscription = new FamilyRecord(current);
                body.Children.Add(new Label { Text = subscription.Text("planCode") == "vip-home-plus" ? "VIP 家庭+" : subscription.Text("planCode"),
                    FontSize = 20, FontAttributes = FontAttributes.Bold });
                body.Children.Add(new Label { Text = "有效至 " + subscription.Text("expiresAt").Split('T')[0], TextColor = Colors.DimGray });
            }
            else body.Children.Add(new Label { Text = "标准版 · 基础功能已包含", FontSize = 17 });
            body.Children.Add(new Label { Text = "套餐功能", FontSize = 18, FontAttributes = FontAttributes.Bold });
            body.Children.Add(new Label { Text = "✓ 基础功能 · " + (snapshot.Bool("standardIncluded") ? "已包含" : "未开通") });
            body.Children.Add(new Label { Text = "✓ VIP 表盘 · " + (snapshot.Bool("vipWatchFaces") ? "已开通" : "未开通") });
        }
        catch (Exception ex)
        {
            body.Children.Clear();
            body.Children.Add(new Label { Text = "读取套餐权益失败：" + ex.Message, TextColor = Colors.DarkRed });
        }
        finally
        {
            var refresh = new Button { Text = "刷新权益" };
            refresh.Clicked += async (_, _) => await LoadAsync();
            body.Children.Add(refresh);
            loading = false;
        }
    }
}
