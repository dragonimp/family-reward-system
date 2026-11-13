using System.Text.Json;

namespace LinkoFamily;

internal sealed class DiningCirclePage : ContentPage
{
    private const string Endpoint = "/api/dining/circle";
    private readonly FamilyStore store;
    private readonly DiningPlace? place;
    private readonly VerticalStackLayout rows = new() { Padding = 20, Spacing = 12 };
    private readonly Entry note = new() { Placeholder = "感受（选填）", MaxLength = 1000 };
    private readonly Label status = MomentStyle.Caption("");
    private readonly Dictionary<Guid, Guid> gatheringDrafts = new();
    private readonly Dictionary<Guid, (Guid Id, string Text)> commentDrafts = new();
    private Guid draft = Guid.NewGuid();
    private bool busy;

    public DiningCirclePage(FamilyStore store, DiningPlace? place)
    {
        this.store = store;
        this.place = place;
        Title = "我的饭圈";
        BackgroundColor = MomentStyle.Background;
        Content = new ScrollView { Content = rows };
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        _ = Run();
    }

    private Task<JsonElement> Send(string path, HttpMethod method, object? body = null) =>
        store.CallAsync(Endpoint + path, method, body);

    private async Task Run(Func<Task>? action = null)
    {
        if (busy) return;
        busy = true;
        var session = store.SessionVersion;
        rows.IsEnabled = false;
        try
        {
            if (action is not null) await action();
            var buddies = (await store.CallAsync(Endpoint + "/buddies")).EnumerateArray().ToArray();
            var posts = (await store.CallAsync(Endpoint + "/posts")).EnumerateArray().ToArray();
            var invitations = (await store.CallAsync(Endpoint + "/invitations")).EnumerateArray().ToArray();
            var restaurants = (await store.CallAsync(Endpoint + "/restaurants")).EnumerateArray().ToArray();
            if (session != store.SessionVersion) { rows.Clear(); return; }
            Render(buddies, posts, invitations, restaurants);
        }
        catch (Exception)
        {
            rows.Clear();
            status.Text = "饭圈操作未完成，请刷新重试。";
            rows.Add(status);
            rows.Add(MomentStyle.Action("刷新饭圈", () => _ = Run()));
        }
        finally { rows.IsEnabled = true; busy = false; }
    }

    private void Render(JsonElement[] buddies, JsonElement[] posts, JsonElement[] invitations, JsonElement[] restaurants)
    {
        rows.Clear();
        var mutual = buddies.Where(x => x.GetProperty("incoming").GetBoolean() && x.GetProperty("outgoing").GetBoolean())
            .Select(x => x.GetProperty("userId").GetString()!).ToArray();
        rows.Add(MomentStyle.Action("刷新饭圈", () => _ = Run()));
        if (place is { } restaurant)
        {
            rows.Add(MomentStyle.Title("分享当前餐厅", 18));
            rows.Add(MomentStyle.Caption(restaurant.Name));
            rows.Add(note);
            rows.Add(MomentStyle.Action("分享到饭圈", async () =>
            {
                var permission = await ChoosePermission(mutual);
                if (permission is null) return;
                await Run(async () =>
                {
                    await Send("/posts", HttpMethod.Post, new
                    {
                        id = draft, restaurantId = restaurant.Id, restaurantName = restaurant.Name,
                        note = note.Text ?? "", visibility = permission.Value.Scope, buddyIds = permission.Value.Buddies
                    });
                    draft = Guid.NewGuid();
                    note.Text = "";
                });
            }));
        }
        rows.Add(MomentStyle.Title("饭搭子", 18));
        foreach (var buddy in buddies)
        {
            var id = buddy.GetProperty("userId").GetString()!;
            var outgoing = buddy.GetProperty("outgoing").GetBoolean();
            var incoming = buddy.GetProperty("incoming").GetBoolean();
            rows.Add(MomentStyle.Caption($"{BuddyLabel(id)} · 共同就餐 {buddy.GetProperty("sharedCount").GetInt32()} 次"));
            var title = outgoing ? (incoming ? "解除饭搭子连接" : "撤回连接请求") : (incoming ? "确认连接" : "请求连接");
            rows.Add(MomentStyle.Action(title, () => _ = Run(() =>
                Send("/buddies/" + Uri.EscapeDataString(id), HttpMethod.Put, new { enabled = !outgoing }))));
        }
        rows.Add(MomentStyle.Title("约饭邀请", 18));
        foreach (var item in invitations.Where(x => x.GetProperty("status").GetString() == "pending" && x.GetProperty("endedAt").ValueKind == JsonValueKind.Null))
        {
            var id = item.GetProperty("gatheringId").GetGuid();
            rows.Add(MomentStyle.Caption(item.GetProperty("restaurantName").GetString()!));
            rows.Add(MomentStyle.Action("接受", () => _ = Run(() => Send($"/invitations/{id:D}", HttpMethod.Put, new { accept = true }))));
            rows.Add(MomentStyle.Action("拒绝", () => _ = Run(() => Send($"/invitations/{id:D}", HttpMethod.Put, new { accept = false }))));
        }
        rows.Add(MomentStyle.Title("收藏与想吃", 18));
        foreach (var savedRestaurant in restaurants)
        {
            var name = savedRestaurant.GetProperty("restaurantName").GetString();
            var saved = savedRestaurant.GetProperty("saved").GetBoolean() ? " · 已收藏" : "";
            var wanted = savedRestaurant.GetProperty("wanted").GetBoolean() ? " · 想吃" : "";
            rows.Add(MomentStyle.Caption(name + saved + wanted));
        }
        rows.Add(MomentStyle.Title("美食动态", 18));
        foreach (var post in posts) ShowPost(post, mutual);
    }

    private void ShowPost(JsonElement post, string[] mutual)
    {
        var id = post.GetProperty("id").GetGuid();
        var name = post.GetProperty("restaurantName").GetString()!;
        var restaurant = post.GetProperty("restaurantId").GetString()!;
        var actions = post.GetProperty("myActions").EnumerateArray().Select(x => x.GetString()).ToHashSet();
        var card = new VerticalStackLayout { Spacing = 8 };
        card.Add(MomentStyle.Title(name, 18));
        if (post.GetProperty("note").GetString() is { Length: > 0 } text) card.Add(new Label { Text = text });
        foreach (var (kind, title, active) in new[] { ("like", "点赞", "取消赞"), ("save", "收藏", "已收藏"), ("want", "想吃", "已想吃") })
        {
            var enabled = actions.Contains(kind);
            card.Add(MomentStyle.Action(enabled ? active : title, () => _ = Run(() =>
                Send($"/posts/{id:D}/actions/{kind}", HttpMethod.Put, new { enabled = !enabled }))));
        }
        foreach (var comment in post.GetProperty("comments").EnumerateArray())
            card.Add(MomentStyle.Caption(comment.GetString() ?? ""));
        card.Add(MomentStyle.Action("写评论", async () =>
        {
            commentDrafts.TryGetValue(id, out var previous);
            var text = await DisplayPromptAsync("写评论", "评论对能查看此动态的人可见。", maxLength: 500, initialValue: previous.Text ?? "");
            if (string.IsNullOrWhiteSpace(text)) return;
            text = text.Trim();
            var operation = previous.Text == text ? previous.Id : Guid.NewGuid();
            commentDrafts[id] = (operation, text);
            await Run(async () =>
            {
                await Send($"/posts/{id:D}/comments", HttpMethod.Post, new { id = operation, body = text });
                commentDrafts.Remove(id);
            });
        }));
        card.Add(MomentStyle.Action("约饭", async () =>
        {
            var choices = new[] { "创建饭局" }.Concat(mutual.Select(BuddyLabel)).ToArray();
            var choice = await DisplayActionSheetAsync("约饭", "取消", null, choices);
            var index = Array.IndexOf(choices, choice);
            if (index < 0) return;
            await Run(async () =>
            {
                if (!gatheringDrafts.TryGetValue(id, out var gathering)) gatheringDrafts[id] = gathering = Guid.NewGuid();
                await store.CallAsync("/api/dining/gatherings", HttpMethod.Post, new
                { id = gathering, restaurantId = restaurant, restaurantName = name });
                if (index > 0)
                    await Send("/invitations", HttpMethod.Post, new { gatheringId = gathering, buddyId = mutual[index - 1] });
                gatheringDrafts.Remove(id);
                await Navigation.PopAsync();
            });
        }));
        if (post.GetProperty("isMine").GetBoolean())
        {
            card.Add(MomentStyle.Action("修改可见范围", async () =>
            {
                var permission = await ChoosePermission(mutual);
                if (permission is not null) await Run(() => Send($"/posts/{id:D}/visibility", HttpMethod.Put,
                    new { visibility = permission.Value.Scope, buddyIds = permission.Value.Buddies }));
            }));
            card.Add(MomentStyle.Action("删除动态", async () =>
            {
                if (await DisplayAlertAsync("删除动态", "删除后，其他人也无法继续查看。", "删除", "取消"))
                    await Run(() => Send($"/posts/{id:D}", HttpMethod.Delete));
            }));
        }
        rows.Add(MomentStyle.Card(card));
    }

    private async Task<(string Scope, string[] Buddies)?> ChoosePermission(string[] mutual)
    {
        var scopes = new[] { "仅自己", "互相确认的饭搭子", "指定饭搭子" };
        var choice = await DisplayActionSheetAsync("可见范围", "取消", null, scopes);
        if (choice == scopes[0]) return ("private", []);
        if (choice == scopes[1]) return ("buddies", []);
        if (choice != scopes[2] || mutual.Length == 0) return null;
        var labels = mutual.Select(BuddyLabel).ToArray();
        var index = Array.IndexOf(labels, await DisplayActionSheetAsync(scopes[2], "取消", null, labels));
        return index >= 0 ? ("selected", [mutual[index]]) : null;
    }

    private static string BuddyLabel(string id) => "饭搭子 " + id[^Math.Min(6, id.Length)..];
}
