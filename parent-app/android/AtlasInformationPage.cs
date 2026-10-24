using System.Text.Json;

namespace LinkoFamily;

public sealed class AtlasInformationPage : ContentPage
{
    private static readonly HttpClient Client = new() { BaseAddress = new Uri("https://home.ai.impx.net/"),
        Timeout = TimeSpan.FromSeconds(15) };
    private readonly bool members;
    private readonly VerticalStackLayout body = new() { Spacing = 14, Padding = new Thickness(20, 20, 20, 36) };
    private bool loading;

    public AtlasInformationPage(bool members)
    {
        this.members = members;
        Title = members ? "同行共创成员" : "隐私与帮助";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        Content = new ScrollView { Content = body };
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await RefreshAsync();
    }

    private async Task RefreshAsync()
    {
        if (loading) return;
        loading = true;
        body.Children.Clear();
        body.Add(new ActivityIndicator { IsRunning = true });
        try
        {
            var path = members ? "api/projects/family-reward/members"
                : "api/capabilities/apps/linko-family-ios/resources";
            using var request = new HttpRequestMessage(HttpMethod.Get, path);
            request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
            using var response = await Client.SendAsync(request);
            if (!response.IsSuccessStatusCode) throw new HttpRequestException("应用资料暂不可用。");
            using var document = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync());
            var root = document.RootElement;
            var key = members ? "projectCode" : "appCode";
            var expected = members ? "family-reward" : "linko-family-ios";
            if (root.GetProperty(key).GetString() != expected) throw new InvalidDataException("资料来源不正确。");
            body.Children.Clear();
            if (members) RenderMembers(root); else RenderResources(root);
        }
        catch (Exception ex)
        {
            body.Children.Clear();
            body.Add(new Label { Text = ex.Message, TextColor = Colors.DarkRed });
        }
        finally
        {
            var refresh = new Button { Text = "刷新" };
            refresh.Clicked += async (_, _) => await RefreshAsync();
            body.Add(refresh);
            loading = false;
        }
    }

    private void RenderMembers(JsonElement root)
    {
        foreach (var (property, heading) in new[] { ("humans", "人类成员"), ("agents", "智能体成员") })
        {
            body.Add(new Label { Text = heading, FontSize = 19, FontAttributes = FontAttributes.Bold });
            var rows = root.GetProperty(property).EnumerateArray().ToArray();
            if (rows.Length == 0) body.Add(new Label { Text = "暂无公开成员", TextColor = Colors.DimGray });
            foreach (var row in rows)
            {
                var name = row.GetProperty("name").GetString();
                if (string.IsNullOrWhiteSpace(name)) continue;
                body.Add(new Label { Text = name, FontAttributes = FontAttributes.Bold });
                body.Add(new Label { Text = row.GetProperty("role").GetString() ?? "", TextColor = Colors.DimGray });
            }
        }
    }

    private void RenderResources(JsonElement root)
    {
        foreach (var (key, label) in new[] { ("privacyPolicyUrl", "隐私政策"), ("termsUrl", "用户协议"),
                     ("userManualUrl", "使用手册"), ("supportUrl", "联系支持") })
        {
            var raw = root.GetProperty(key).GetString();
            if (Uri.TryCreate(raw, UriKind.Absolute, out var url) && url.Scheme == Uri.UriSchemeHttps
                && url.UserInfo.Length == 0)
            {
                var button = new Button { Text = label };
                button.Clicked += async (_, _) => await Browser.Default.OpenAsync(url);
                body.Add(button);
            }
            else body.Add(new Label { Text = label + "未配置", TextColor = Colors.DimGray });
        }
    }
}
