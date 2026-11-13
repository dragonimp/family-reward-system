using System.Text.Json;
using QRCoder;

namespace LinkoFamily;

internal sealed class DiningGatheringsPage : ContentPage
{
    private const string Endpoint = "/api/dining/gatherings";
    private readonly FamilyStore store;
    private readonly VerticalStackLayout rows = new() { Spacing = 12 };
    private readonly Label status = MomentStyle.Caption("");
    private Guid operation = Guid.NewGuid();
    private readonly VerticalStackLayout content = new() { Spacing = 12, Padding = 20 };

    public DiningGatheringsPage(FamilyStore store, DiningPlace? place)
    {
        this.store = store;
        Title = "一起干饭";
        BackgroundColor = MomentStyle.Background;
        if (place is not null)
            content.Add(MomentStyle.Action($"为「{place.Name}」创建饭局", () => _ = Update("", new
            {
                id = operation, restaurantId = place.Id, restaurantName = place.Name
            })));
        var code = new Entry { Placeholder = "粘贴饭局口令" };
        content.Add(code);
        content.Add(MomentStyle.Action("扫描饭局二维码", async () =>
        {
            try
            {
                var file = await MediaPicker.Default.CapturePhotoAsync();
                if (file is not null && Guid.TryParseExact(await AndroidQrImage.ReadAsync(file), "D", out var value))
                    code.Text = value.ToString("D");
                else if (file is not null) status.Text = "未识别到饭局二维码。";
            }
            catch (Exception) { status.Text = "无法读取二维码，请检查相机权限或粘贴口令。"; }
        }));
        content.Add(MomentStyle.Action("加入饭局", () =>
        {
            if (Guid.TryParseExact(code.Text?.Trim(), "D", out var value)) _ = Update("/join", new { code = value });
            else status.Text = "请输入完整饭局口令。";
        }));
        content.Add(MomentStyle.Action("刷新饭局", () => _ = Update()));
        content.Add(status);
        content.Add(rows);
        Content = new ScrollView { Content = content };
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        _ = Update();
    }

    private async Task Update(string? path = null, object? body = null)
    {
        if (!content.IsEnabled) return;
        var session = store.SessionVersion;
        content.IsEnabled = false;
        try
        {
            if (path is not null)
            {
                await store.CallAsync(Endpoint + path, HttpMethod.Post, body);
                if (path.Length == 0) operation = Guid.NewGuid();
            }
            var items = await store.CallAsync(Endpoint);
            if (session != store.SessionVersion) { rows.Clear(); return; }
            rows.Clear();
            foreach (var item in items.EnumerateArray()) Show(item);
            status.Text = "";
        }
        catch (Exception)
        {
            if (session != store.SessionVersion) rows.Clear();
            status.Text = "饭局操作未完成，请核对口令或刷新重试。";
        }
        finally { content.IsEnabled = true; }
    }

    private void Show(JsonElement item)
    {
        var id = item.GetProperty("id").GetGuid();
        var ended = item.GetProperty("endedAt").ValueKind == JsonValueKind.String;
        var members = item.GetProperty("members");
        var confirmed = members.EnumerateArray().Count(member => member.GetProperty("confirmedAt").ValueKind == JsonValueKind.String);
        var card = new VerticalStackLayout { Spacing = 8 };
        card.Add(MomentStyle.Title(item.GetProperty("restaurantName").GetString() ?? "", 18));
        card.Add(MomentStyle.Caption($"{(ended ? "已结束" : "进行中")} · {members.GetArrayLength()} 人已加入 · {confirmed} 人已确认"));
        foreach (var member in members.EnumerateArray())
        {
            var userId = member.GetProperty("userId").GetString() ?? "";
            card.Add(MomentStyle.Caption("参与者 " + userId[^Math.Min(6, userId.Length)..]));
        }
        if (item.GetProperty("joinCode").GetString() is { } code)
        {
            card.Add(MomentStyle.Action("显示饭局二维码", async () =>
            {
                using var generator = new QRCodeGenerator();
                using var data = generator.CreateQrCode(code, QRCodeGenerator.ECCLevel.M);
                var bytes = new PngByteQRCode(data).GetGraphic(8);
                await Navigation.PushAsync(new ContentPage
                {
                    Title = "面对面扫码加入",
                    Content = new VerticalStackLayout
                    {
                        Padding = 24, Spacing = 16,
                        Children =
                        {
                            new Image { Source = ImageSource.FromStream(() => new MemoryStream(bytes)), WidthRequest = 240, HeightRequest = 240 },
                            MomentStyle.Caption(code)
                        }
                    }
                });
            }));
            card.Add(MomentStyle.Action("分享饭局口令", () => _ = Share.Default.RequestAsync(new ShareTextRequest { Text = code, Title = "饭局口令" })));
        }
        if (!ended && item.GetProperty("myConfirmedAt").ValueKind == JsonValueKind.Null)
            card.Add(MomentStyle.Action("确认就餐", () => _ = Update($"/{id:D}/confirm", new { })));
        if (!ended && item.GetProperty("isHost").GetBoolean())
            card.Add(MomentStyle.Action("结束饭局", () => _ = Update($"/{id:D}/end", new { })));
        rows.Add(MomentStyle.Card(card));
    }
}
