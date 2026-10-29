namespace LinkoFamily;

public sealed class PrivacyPolicyPage : ContentPage
{
    public const string ConsentKey = "linko_family_privacy_1_3_accepted";
    private readonly WebView policy = new();

    public PrivacyPolicyPage()
    {
        Title = "隐私政策";
        var close = new Button { Text = "关闭" };
        close.Clicked += async (_, _) => await Navigation.PopModalAsync();
        var header = new Grid
        {
            ColumnDefinitions = new ColumnDefinitionCollection
            {
                new(GridLength.Star), new(GridLength.Auto)
            },
            Padding = new Thickness(16, 8)
        };
        header.Add(new Label
        {
            Text = "Linko Moment 隐私政策",
            FontSize = 20,
            FontAttributes = FontAttributes.Bold,
            VerticalTextAlignment = TextAlignment.Center
        }, 0, 0);
        header.Add(close, 1, 0);
        var layout = new Grid
        {
            RowDefinitions = new RowDefinitionCollection
            {
                new(GridLength.Auto),
                new(GridLength.Star)
            }
        };
        layout.Add(header, 0, 0);
        layout.Add(policy, 0, 1);
        Content = layout;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        policy.Source = new HtmlWebViewSource { Html = await LoadHtmlAsync() };
    }

    public static async Task<string> LoadHtmlAsync()
    {
        await using var stream = await FileSystem.OpenAppPackageFileAsync("linko-family-privacy.html");
        using var reader = new StreamReader(stream);
        var html = await reader.ReadToEndAsync();
        return html.Replace(
            "<link rel=\"stylesheet\" href=\"/legal/legal.css\">",
            "<style>body{font-family:sans-serif;color:#173b35;line-height:1.6;padding:16px}h1{font-size:23px}h2{font-size:19px;margin-top:24px}a{color:#0f766e}li{margin:8px 0}</style>",
            StringComparison.Ordinal);
    }
}

public sealed class PrivacyGatePage : ContentPage
{
    private readonly WebView policy = new();
    private readonly Button agree = new() { Text = "同意并继续", IsEnabled = false };
    private readonly Label message = new() { TextColor = Colors.DimGray, FontSize = 13 };
    private bool loaded;

    public PrivacyGatePage(Action onAgree)
    {
        Title = "隐私政策";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        agree.Clicked += (_, _) =>
        {
            Preferences.Default.Set(PrivacyPolicyPage.ConsentKey, true);
            onAgree();
        };
        var reject = new Button { Text = "拒绝" };
        reject.Clicked += (_, _) =>
            message.Text = "你已拒绝隐私政策，应用功能不会启动。可以关闭应用，或阅读后重新选择。";

        var header = new VerticalStackLayout { Padding = new Thickness(16, 16, 16, 8), Spacing = 8 };
        header.Add(new Label { Text = "使用 Linko Moment 前，请阅读隐私政策",
            FontSize = 20, FontAttributes = FontAttributes.Bold });
        header.Add(new Label { Text = "我们处理账号、家庭与孩子资料，以及你主动提交的活动内容。下方可直接阅读全文。请选择同意或拒绝。",
            FontSize = 14 });
        var footer = new VerticalStackLayout { Padding = new Thickness(16, 8, 16, 16), Spacing = 6 };
        footer.Add(message);
        footer.Add(agree);
        footer.Add(reject);
        var layout = new Grid
        {
            RowDefinitions = new RowDefinitionCollection
            {
                new(GridLength.Auto), new(GridLength.Star), new(GridLength.Auto)
            }
        };
        layout.Add(header, 0, 0);
        layout.Add(policy, 0, 1);
        layout.Add(footer, 0, 2);
        Content = layout;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        if (loaded) return;
        try
        {
            policy.Source = new HtmlWebViewSource { Html = await PrivacyPolicyPage.LoadHtmlAsync() };
            agree.IsEnabled = true;
            loaded = true;
        }
        catch
        {
            message.Text = "隐私政策暂时无法读取，请重新启动应用。";
        }
    }
}
