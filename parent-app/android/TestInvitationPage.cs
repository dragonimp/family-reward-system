using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using AgentIdentity.NativeClient;
using QRCoder;

namespace LinkoFamily;

public sealed class TestInvitationPage : ContentPage
{
    private static readonly Uri Origin = new("https://home.ai.impx.net/");
    private const string SessionKey = "linko_family_atlas_share_session";
    private readonly NativeSessionHandler session;
    private readonly HttpClient client;
    private readonly VerticalStackLayout body = new() { Spacing = 12, Padding = new Thickness(16, 12, 16, 16) };
    private readonly VerticalStackLayout invitationCard = new() { Spacing = 10, IsVisible = false };
    private readonly Label title = new() { FontSize = 23, FontAttributes = FontAttributes.Bold, HorizontalTextAlignment = TextAlignment.Center };
    private readonly Label description = new() { TextColor = Colors.DimGray, HorizontalTextAlignment = TextAlignment.Center };
    private readonly Label error = new() { TextColor = Colors.DarkRed, HorizontalTextAlignment = TextAlignment.Center };
    private readonly Label link = new() { LineBreakMode = LineBreakMode.CharacterWrap, TextColor = Color.FromArgb("#0F766E") };
    private readonly Image qr = new() { WidthRequest = 184, HeightRequest = 184, HorizontalOptions = LayoutOptions.Center };
    private readonly ActivityIndicator progress = new();
    private readonly Button generate = new() { Text = "登录并生成邀请" };
    private Uri? invitation;
    private string invitationTitle = "Linko Moment";
    private bool busy;
    private CancellationTokenSource? loginCancellation;

    public TestInvitationPage()
    {
        Title = "专属测试邀请";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        session = new NativeSessionHandler(Origin,
            () => SecureStorage.Default.GetAsync(SessionKey),
            value => value is null ? ClearSessionAsync() : SecureStorage.Default.SetAsync(SessionKey, value));
        client = new HttpClient(session) { BaseAddress = Origin, Timeout = TimeSpan.FromSeconds(25) };
        body.Add(new Label { Text = "✉", FontSize = 34, HorizontalTextAlignment = TextAlignment.Center });
        body.Add(title);
        body.Add(description);
        invitationCard.Add(new Border { Content = qr, Padding = 8, BackgroundColor = Colors.White,
            StrokeThickness = 0, HorizontalOptions = LayoutOptions.Center });
        invitationCard.Add(new Label { Text = "扫码打开邀请", FontAttributes = FontAttributes.Bold,
            HorizontalTextAlignment = TextAlignment.Center });
        var linkButton = new Button { Text = "打开邀请链接" };
        linkButton.Clicked += async (_, _) => { if (invitation is not null) await Browser.Default.OpenAsync(invitation); };
        invitationCard.Add(link);
        invitationCard.Add(linkButton);
        var copy = new Button { Text = "复制链接" };
        copy.Clicked += async (_, _) =>
        {
            if (invitation is null) return;
            await Clipboard.Default.SetTextAsync(invitation.AbsoluteUri);
            copy.Text = "已复制";
        };
        var share = new Button { Text = "分享邀请", BackgroundColor = Color.FromArgb("#0F766E"), TextColor = Colors.White };
        share.Clicked += async (_, _) =>
        {
            if (invitation is not null)
                await Share.Default.RequestAsync(new ShareTextRequest { Title = invitationTitle + " 测试邀请", Text = invitation.AbsoluteUri });
        };
        var actions = new HorizontalStackLayout { Spacing = 12, HorizontalOptions = LayoutOptions.Center };
        actions.Add(copy); actions.Add(share);
        invitationCard.Add(actions);
        body.Add(invitationCard);
        body.Add(progress);
        generate.Clicked += async (_, _) => await CreateAsync();
        body.Add(generate);
        body.Add(error);
        Content = new ScrollView { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Never };
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await LoadDetailsAsync();
        if (invitation is null && !string.IsNullOrWhiteSpace(await session.GetTokenAsync())) await CreateAsync();
    }

    private async Task LoadDetailsAsync()
    {
        try
        {
            using var response = await client.GetAsync("api/marketplace/apps/linko-family-ios/sharing");
            if (!response.IsSuccessStatusCode) throw new InvalidOperationException("此应用暂未配置测试邀请。");
            using var json = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync());
            title.Text = json.RootElement.GetProperty("title").GetString() ?? "专属测试邀请";
            description.Text = json.RootElement.GetProperty("description").GetString() ?? "";
        }
        catch (Exception ex) { error.Text = ex.Message; }
    }

    private async Task CreateAsync()
    {
        if (busy) return;
        busy = true; error.Text = ""; generate.IsEnabled = false;
        progress.IsRunning = invitation is null; progress.IsVisible = progress.IsRunning;
        try
        {
            var token = await session.GetTokenAsync();
            if (string.IsNullOrWhiteSpace(token))
            {
                loginCancellation = new CancellationTokenSource();
                using var loginHttp = new HttpClient { BaseAddress = Origin, Timeout = TimeSpan.FromSeconds(30) };
                var login = new NativeLoginClient(loginHttp);
                var result = await login.LoginSessionAsync(
                    async (url, ct) => { await Launcher.Default.OpenAsync(url); ct.ThrowIfCancellationRequested(); return true; },
                    code => MainThread.BeginInvokeOnMainThread(() => description.Text = $"本次登录验证码：{code}"),
                    false, loginCancellation.Token);
                await session.SaveAsync(result, loginCancellation.Token);
                loginCancellation.Dispose(); loginCancellation = null;
                await LoadDetailsAsync();
                token = await session.GetTokenAsync();
            }
            if (string.IsNullOrWhiteSpace(token)) throw new InvalidOperationException("请先登录用户中心。");
            using var request = new HttpRequestMessage(HttpMethod.Post, "api/marketplace/apps/linko-family-ios/share-links");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            using var response = await client.SendAsync(request);
            if (!response.IsSuccessStatusCode) throw new HttpRequestException("生成邀请失败，请稍后重试。");
            using var json = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync());
            if (!ValidInvitation(json.RootElement.GetProperty("url").GetString(), out var url))
                throw new InvalidDataException("邀请地址无效。");
            invitation = url;
            invitationTitle = json.RootElement.GetProperty("title").GetString() ?? "Linko Moment";
            link.Text = url.AbsoluteUri;
            using var generator = new QRCodeGenerator();
            using var data = generator.CreateQrCode(url.AbsoluteUri, QRCodeGenerator.ECCLevel.M);
            var bytes = new PngByteQRCode(data).GetGraphic(8);
            qr.Source = ImageSource.FromStream(() => new MemoryStream(bytes));
            invitationCard.IsVisible = true;
            generate.Text = "生成新链接";
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { error.Text = ex.Message; generate.Text = invitation is null ? "重试生成邀请" : "生成新链接"; }
        finally {
            loginCancellation?.Dispose(); loginCancellation = null;
            busy = false; generate.IsEnabled = true; progress.IsRunning = false; progress.IsVisible = false;
        }
    }

    private static bool ValidInvitation(string? raw, out Uri url)
    {
        url = null!;
        if (!Uri.TryCreate(raw, UriKind.Absolute, out var value) || value.Scheme != Uri.UriSchemeHttps
            || value.Host != Origin.Host || value.Query.Length > 0 || value.Fragment.Length > 0
            || !value.AbsolutePath.StartsWith("/invite/", StringComparison.Ordinal)) return false;
        var code = value.AbsolutePath["/invite/".Length..];
        if (code.Length is < 16 or > 48 || !code.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_')) return false;
        url = value;
        return true;
    }

    private static Task ClearSessionAsync() { SecureStorage.Default.Remove(SessionKey); return Task.CompletedTask; }
}
