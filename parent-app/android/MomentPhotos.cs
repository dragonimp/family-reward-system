namespace LinkoFamily;

internal sealed class MomentThumbnails(FamilyStore store)
{
    private readonly SemaphoreSlim parallel = new(4);
    private readonly object gate = new();
    private readonly Dictionary<string, byte[]> cache = [];
    private readonly Queue<string> order = new();
    private long bytes;
    public MomentOriginals Originals => store.Originals;
    public void Clear() { lock (gate) { cache.Clear(); order.Clear(); bytes = 0; } }
    public async Task<byte[]> GetAsync(MomentFeedItem item, CancellationToken ct)
    {
        var account = store.SessionVersion;
        var path = item.Scope.Api + $"/native-photos/{item.Record.Id:D}/thumbnail";
        var key = account + path + item.Record.Text("thumbnailRevision");
        lock (gate) if (cache.TryGetValue(key, out var saved)) return saved;
        await parallel.WaitAsync(ct);
        try
        {
            lock (gate) if (cache.TryGetValue(key, out var saved)) return saved;
            var data = await store.ThumbnailAsync(path, ct);
            if (account != store.SessionVersion || !store.Authenticated) throw new OperationCanceledException();
            lock (gate)
            {
                if (cache.TryGetValue(key, out var existing)) return existing;
                cache[key] = data; order.Enqueue(key); bytes += data.Length;
                while (cache.Count > 64 || bytes > 12 * 1024 * 1024)
                    if (cache.Remove(order.Dequeue(), out var old)) bytes -= old.Length;
            }
            return data;
        }
        finally { parallel.Release(); }
    }
}

internal sealed class MomentThumbnail : ContentView
{
    private readonly Image image;
    private readonly Label placeholder = MomentStyle.Caption("照片");
    private readonly MomentThumbnails cache;
    private MomentFeedItem? item;
    private CancellationTokenSource? loading;
    public MomentThumbnail(MomentThumbnails cache, bool grid = false, bool detail = false, bool expanded = false)
    {
        this.cache = cache;
        image = new Image { Aspect = detail ? Aspect.AspectFit : Aspect.AspectFill };
        HeightRequest = detail ? 300 : expanded ? 220 : grid ? 65 : 96;
        if (!grid && !detail && !expanded) WidthRequest = 96;
        var layout = new Grid { BackgroundColor = Color.FromArgb("#E7E9ED") };
        placeholder.HorizontalTextAlignment = TextAlignment.Center; placeholder.VerticalTextAlignment = TextAlignment.Center;
        layout.Add(placeholder); layout.Add(image); Content = layout;
        Loaded += (_, _) => { cache.Originals.Changed += OriginalChanged; _ = LoadAsync(); };
        Unloaded += (_, _) => { cache.Originals.Changed -= OriginalChanged; loading?.Cancel(); image.Source = null; };
    }
    private void OriginalChanged() { image.Source = null; _ = LoadAsync(); }
    public void Bind(MomentFeedItem next)
    {
        loading?.Cancel(); item = next; image.Source = null;
        placeholder.Text = next.Record.Text("contentType").StartsWith("video/", StringComparison.Ordinal) ? "视频" : "照片";
        if (Handler != null) _ = LoadAsync();
    }
    private async Task LoadAsync()
    {
        if (item is not { } current || image.Source != null) return;
        if (cache.Originals.Cached(current) is { } original && !current.Record.Text("contentType").StartsWith("video/", StringComparison.Ordinal)) { image.Source = ImageSource.FromFile(original); return; }
        loading?.Cancel(); var token = loading = new CancellationTokenSource();
        try
        {
            var data = await cache.GetAsync(current, token.Token);
            if (!token.IsCancellationRequested && ReferenceEquals(loading, token)) image.Source = ImageSource.FromStream(() => new MemoryStream(data, false));
        }
        catch (OperationCanceledException) { }
        catch { if (!token.IsCancellationRequested) placeholder.Text = "预览未加载"; }
        finally { if (ReferenceEquals(loading, token)) loading = null; token.Dispose(); }
    }
}

internal sealed class MomentFeedRow : ContentView
{
    private readonly FamilyStore store;
    private readonly Page owner;
    private readonly MomentThumbnails cache;
    private readonly bool grid, expanded;
    private readonly Action refresh;
    private readonly IReadOnlyList<MomentFeedItem> gallery;
    public MomentFeedRow(FamilyStore store, Page owner, MomentThumbnails cache, bool grid, MomentScope scope, Action refresh, IReadOnlyList<MomentFeedItem> gallery, bool expanded = false)
    { this.store = store; this.owner = owner; this.cache = cache; this.grid = grid; this.refresh = refresh; this.gallery = gallery; this.expanded = expanded; }
    protected override void OnBindingContextChanged()
    {
        base.OnBindingContextChanged();
        if (BindingContext is not MomentFeedItem item) { Content = null; return; }
        var photo = item.Record;
        var nickname = photo.Text(item.Kind == "photo" ? "sourceDisplayName" : "authorName");
        if (nickname.Length == 0) nickname = photo.Text("nickname");
        if (nickname.Length == 0) nickname = "活动成员";
        if (item.Kind != "photo")
        {
            Content = MomentStyle.Card(new VerticalStackLayout { Spacing = 8, Children = {
                MomentStyle.Title(nickname + (item.Kind == "checkin" ? " · 打卡" : " · 日常"), 16),
                new Label { Text = item.Kind == "checkin" ? string.Join("\n", new[] { photo.Text("address"), photo.Text("note") }.Where(s => s.Length > 0)) : photo.Text("text"), FontSize = 16, TextColor = MomentStyle.Ink },
                MomentStyle.Caption(MomentDates.LocalTime(photo)) } }); return;
        }
        var preview = new MomentThumbnail(cache, grid, expanded: expanded); preview.Bind(item);
        var open = new Action(async () => await owner.Navigation.PushAsync(new MomentPhotoPage(store, cache, item, gallery)));
        var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => open(); preview.GestureRecognizers.Add(tap);
        if (grid)
        {
            var name = new Label { Text = nickname, FontSize = 11, MaxLines = 1, LineBreakMode = LineBreakMode.TailTruncation, TextColor = MomentStyle.Ink };
            Content = new VerticalStackLayout { Spacing = 4, Children = { preview, name } }; return;
        }
        var info = new VerticalStackLayout { Spacing = 4 };
        info.Add(MomentStyle.Title(nickname, 16));
        info.Add(MomentStyle.Caption(Place(photo)));
        info.Add(MomentStyle.Caption(MomentDates.LocalTime(photo)));
        var actions = new HorizontalStackLayout { Spacing = 3 };
        if (photo.Flag("canDelete")) actions.Add(MomentStyle.Action("删除", () => _ = DeleteAsync(item)));
        actions.Add(MomentStyle.Action($"点评 {photo.Number("commentCount") ?? 0:0}", open));
        if (expanded)
        {
            var card = new VerticalStackLayout { Spacing = 9 };
            card.Add(MomentStyle.Title(nickname, 17)); card.Add(MomentStyle.Caption(MomentDates.LocalTime(photo))); card.Add(preview);
            card.Add(MomentStyle.Caption(Place(photo))); card.Add(actions); Content = MomentStyle.Card(card, new Thickness(12)); return;
        }
        var row = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Auto), new(GridLength.Star) }, ColumnSpacing = 12 };
        info.Add(actions);
        row.Add(preview); row.Add(info, 1, 0); Content = MomentStyle.Card(row, new Thickness(12));
    }
    internal static string Place(MomentRecord photo)
    {
        var name = photo.Text("locationName"); if (name.Length == 0) name = "地点未命名";
        return name + (photo.Number("altitudeMeters") is { } altitude ? $" · 海拔 {altitude:0.#} 米" : " · 海拔未记录");
    }
    private async Task DeleteAsync(MomentFeedItem item)
    {
        if (!await owner.DisplayAlertAsync("删除这项分享？", "活动成员将无法再获取此文件；设备相册原件保留。", "删除分享", "取消")) return;
        IsEnabled = false; var account = store.SessionVersion;
        try { await store.CallAsync(item.Scope.Api + $"/live/photos/{item.Record.Id:D}", HttpMethod.Delete); if (account == store.SessionVersion) refresh(); }
        catch (Exception error) { await owner.DisplayAlertAsync("删除未完成", error.Message, "知道了"); }
        finally { IsEnabled = true; }
    }
}

internal sealed class MomentPhotoPage : ContentPage
{
    private readonly FamilyStore store;
    private MomentFeedItem item;
    private readonly IReadOnlyList<MomentFeedItem> gallery;
    private readonly Label fileName = MomentStyle.Title("", 18), source = new(), place = MomentStyle.Caption(""), time = MomentStyle.Caption(""), device = MomentStyle.Caption(""), position = MomentStyle.Caption("");
    private readonly Button fetchOriginal, saveOriginal, shareOriginal, openOriginal;
    private readonly Label transferStatus = MomentStyle.Caption("");
    private CancellationTokenSource? transfer;
    private bool originalBusy, originalSaved;
    private int selection;
    private readonly VerticalStackLayout comments = new() { Spacing = 10 };
    private readonly Label error = MomentStyle.Caption("");
    private CancellationTokenSource? loading;
    private int skip;
    private bool hasMore, busy;
    private string Route => item.Scope.Api + $"/native-photos/{item.Record.Id:D}/comments";
    public MomentPhotoPage(FamilyStore store, MomentThumbnails cache, MomentFeedItem item, IReadOnlyList<MomentFeedItem>? gallery = null)
    {
        this.store = store; this.item = item; this.gallery = gallery ?? new[] { item };
        var initial = this.gallery.ToList().FindIndex(p => p.Record.Id == item.Record.Id && p.Scope == item.Scope);
        Title = "照片详情"; BackgroundColor = MomentStyle.Background; SafeAreaEdges = SafeAreaEdges.All;
        var carousel = new CarouselView { ItemsSource = this.gallery, Position = Math.Max(0, initial), Loop = false, HeightRequest = 300, ItemTemplate = new DataTemplate(() =>
        {
            var preview = new MomentThumbnail(cache, detail: true) { IsClippedToBounds = true };
            preview.BindingContextChanged += (_, _) => { if (preview.BindingContext is MomentFeedItem row) preview.Bind(row); };
            var zoom = new PinchGestureRecognizer(); zoom.PinchUpdated += (_, e) => { if (e.Status == GestureStatus.Running && double.IsFinite(e.Scale)) preview.Scale = Math.Clamp(preview.Scale * e.Scale, 1, 4); }; preview.GestureRecognizers.Add(zoom);
            var fullscreen = new TapGestureRecognizer();
            fullscreen.Tapped += async (_, _) =>
            {
                if (preview.BindingContext is not MomentFeedItem selected) return;
                var photo = new MomentThumbnail(cache, detail: true) { HeightRequest = -1 };
                photo.Bind(selected);
                var page = new ContentPage { BackgroundColor = Colors.Black, SafeAreaEdges = SafeAreaEdges.All };
                var close = MomentStyle.Action("关闭", async () => await Navigation.PopModalAsync());
                var layout = new Grid { RowDefinitions = new RowDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
                layout.Add(photo); layout.Add(close, 0, 1); page.Content = layout;
                var pinch = new PinchGestureRecognizer();
                pinch.PinchUpdated += (_, e) =>
                {
                    if (e.Status == GestureStatus.Running && double.IsFinite(e.Scale))
                        photo.Scale = Math.Clamp(photo.Scale * e.Scale, 1, 4);
                };
                photo.GestureRecognizers.Add(pinch);
                var doubleTap = new TapGestureRecognizer { NumberOfTapsRequired = 2 };
                doubleTap.Tapped += (_, _) => photo.Scale = photo.Scale > 1 ? 1 : 2;
                photo.GestureRecognizers.Add(doubleTap);
                var dismiss = new SwipeGestureRecognizer { Direction = SwipeDirection.Down };
                dismiss.Swiped += async (_, _) => { if (photo.Scale <= 1) await Navigation.PopModalAsync(); };
                photo.GestureRecognizers.Add(dismiss);
                await Navigation.PushModalAsync(page);
            };
            preview.GestureRecognizers.Add(fullscreen);
            var down = new SwipeGestureRecognizer { Direction = SwipeDirection.Down }; down.Swiped += async (_, _) => { if (preview.Scale <= 1) await Navigation.PopAsync(); }; preview.GestureRecognizers.Add(down);
            return preview;
        }) };
        carousel.PositionChanged += async (_, e) =>
        {
            if (e.CurrentPosition < 0 || e.CurrentPosition >= this.gallery.Count) return;
            transfer?.Cancel(); originalBusy = false; originalSaved = false;
            loading?.Cancel(); selection++; busy = false; skip = 0; hasMore = false; comments.Children.Clear();
            this.item = this.gallery[e.CurrentPosition]; UpdateInfo(e.CurrentPosition); await LoadCommentsAsync(true);
        };
        var paging = new HorizontalStackLayout { Spacing = 10, HorizontalOptions = LayoutOptions.Center };
        paging.Add(MomentStyle.Action("‹ 上一张", () => carousel.Position = Math.Max(0, carousel.Position - 1)));
        paging.Add(position); paging.Add(MomentStyle.Action("下一张 ›", () => carousel.Position = Math.Min(this.gallery.Count - 1, carousel.Position + 1)));
        var body = new VerticalStackLayout { Padding = 16, Spacing = 14 };
        body.Add(carousel); body.Add(paging); body.Add(fileName); body.Add(source); body.Add(place); body.Add(time); body.Add(device);
        fetchOriginal = MomentStyle.Action("获取原文件", () => _ = FetchOriginalAsync(), true);
        saveOriginal = MomentStyle.Action("保存到相册", () => _ = UseOriginalAsync(true));
        shareOriginal = MomentStyle.Action("分享原文件", () => _ = UseOriginalAsync(false));
        openOriginal = MomentStyle.Action("打开原文件", () => _ = OpenOriginalAsync());
        body.Add(fetchOriginal); body.Add(transferStatus);
        body.Add(new HorizontalStackLayout { Spacing = 8, Children = { saveOriginal, shareOriginal, openOriginal } });
        body.Add(MomentStyle.Title("照片点评", 20)); body.Add(MomentStyle.Action("发表点评", () => _ = PostAsync()));
        body.Add(error); body.Add(comments);
        body.Add(MomentStyle.Action("加载更多点评", () => _ = LoadCommentsAsync(false)));
        body.Add(MomentStyle.Action("刷新点评", () => _ = LoadCommentsAsync(true)));
        Content = new ScrollView { Content = body }; UpdateInfo(Math.Max(0, initial));
    }
    private void UpdateInfo(int index)
    {
        fileName.Text = item.Record.Text("originalFileName"); source.Text = "分享者：" + item.Record.Text("sourceDisplayName");
        place.Text = MomentFeedRow.Place(item.Record); time.Text = MomentDates.LocalTime(item.Record);
        device.Text = "来源设备：" + string.Join(" · ", new[] { item.Record.Text("sourceDeviceName"), item.Record.Text("sourceDeviceModel"), item.Record.Text("sourceDevicePlatform") }.Where(s => s.Length > 0));
        position.Text = $"{index + 1} / {gallery.Count}";
        transferStatus.Text = ""; UpdateOriginalActions();
    }
    protected override async void OnAppearing() { base.OnAppearing(); await LoadCommentsAsync(true); }
    protected override void OnDisappearing() { transfer?.Cancel(); originalBusy = false; selection++; loading?.Cancel(); busy = false; base.OnDisappearing(); }
    private void UpdateOriginalActions()
    {
        var available = store.Originals.Cached(item) != null;
        fetchOriginal.IsVisible = !available; fetchOriginal.IsEnabled = !originalBusy;
        fetchOriginal.Text = originalBusy ? "正在获取原文件…" : "获取原文件";
        saveOriginal.IsVisible = shareOriginal.IsVisible = openOriginal.IsVisible = available;
        saveOriginal.IsEnabled = !originalBusy && !originalSaved;
        saveOriginal.Text = originalSaved ? "已保存到相册" : "保存到相册";
        shareOriginal.IsEnabled = openOriginal.IsEnabled = !originalBusy;
    }
    private async Task FetchOriginalAsync()
    {
        if (originalBusy) return;
        var current = selection; var account = store.SessionVersion; var selected = item;
        transfer?.Cancel(); using var cancellation = transfer = new CancellationTokenSource();
        bool Active() => current == selection && account == store.SessionVersion && !cancellation.IsCancellationRequested;
        originalBusy = true; UpdateOriginalActions();
        try
        {
            var progress = new Progress<double>(value => { if (Active()) transferStatus.Text = $"正在接收原文件：{value * 100:0}%"; });
            await store.Originals.DownloadAsync(selected, text => { if (Active()) transferStatus.Text = text; }, progress, cancellation.Token);
            if (Active()) transferStatus.Text = "原文件已获取，可以查看、保存或分享。";
        }
        catch (OperationCanceledException) { }
        catch (Exception exception) { if (Active()) transferStatus.Text = exception is FamilyApiException ? exception.Message : "原文件获取未完成，请重试。分享者可能需要保持 App 打开。"; }
        finally { if (transfer == cancellation) { transfer = null; originalBusy = false; if (current == selection) UpdateOriginalActions(); } }
    }
    private async Task UseOriginalAsync(bool save)
    {
        if (originalBusy || store.Originals.Cached(item) is not { } file) return;
        var current = selection; var account = store.SessionVersion;
        var selected = item; using var cancellation = transfer = new CancellationTokenSource();
        originalBusy = true; UpdateOriginalActions();
        try
        {
            if (save) await MomentMediaLibrary.SaveAsync(file, selected.Record.Text("contentType"), selected.Record.Text("originalFileName"), cancellation.Token);
            else await Share.Default.RequestAsync(new ShareFileRequest("分享原文件", new ShareFile(file, selected.Record.Text("contentType"))));
            if (save && current == selection && account == store.SessionVersion && !cancellation.IsCancellationRequested && OperatingSystem.IsAndroidVersionAtLeast(29)) originalSaved = true;
        }
        catch (OperationCanceledException) { }
        catch { if (current == selection && account == store.SessionVersion) transferStatus.Text = "操作未完成，请重试。"; }
        finally { if (transfer == cancellation) { transfer = null; originalBusy = false; if (current == selection) UpdateOriginalActions(); } }
    }
    private async Task OpenOriginalAsync()
    {
        if (store.Originals.Cached(item) is not { } file) return;
        if (item.Record.Text("contentType").StartsWith("video/", StringComparison.Ordinal))
        {
            try { await Launcher.Default.OpenAsync(new OpenFileRequest("原视频", new ReadOnlyFile(file, item.Record.Text("contentType")))); }
            catch { transferStatus.Text = "未找到可打开此视频的应用，可以分享原文件。"; }
            return;
        }
        var photo = new Image { Source = ImageSource.FromFile(file), Aspect = Aspect.AspectFit };
        var page = new ContentPage { BackgroundColor = Colors.Black, SafeAreaEdges = SafeAreaEdges.All };
        var grid = new Grid { RowDefinitions = new RowDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
        grid.Add(photo); grid.Add(MomentStyle.Action("关闭", async () => await Navigation.PopModalAsync()), 0, 1); page.Content = grid;
        var pinch = new PinchGestureRecognizer(); pinch.PinchUpdated += (_, e) => { if (e.Status == GestureStatus.Running && double.IsFinite(e.Scale)) photo.Scale = Math.Clamp(photo.Scale * e.Scale, 1, 4); }; photo.GestureRecognizers.Add(pinch);
        await Navigation.PushModalAsync(page);
    }
    private async Task LoadCommentsAsync(bool reset)
    {
        if (busy || !reset && !hasMore) return;
        busy = true; var account = store.SessionVersion; var current = selection; loading?.Cancel(); var cancellation = loading = new CancellationTokenSource();
        try
        {
            var data = await store.CallAsync(Route + $"?skip={(reset ? 0 : skip)}", ct: cancellation.Token);
            var rows = MomentRecord.List(data.GetProperty("items"));
            if (cancellation.IsCancellationRequested || current != selection || account != store.SessionVersion) return;
            if (reset) comments.Children.Clear();
            foreach (var row in rows)
            {
                var stack = new VerticalStackLayout { Spacing = 5 };
                stack.Add(MomentStyle.Title(row.Text("authorName"), 16)); stack.Add(new Label { Text = row.Text("text"), FontSize = 16 }); stack.Add(MomentStyle.Caption(MomentDates.LocalTime(row)));
                comments.Add(MomentStyle.Card(stack));
            }
            hasMore = data.GetProperty("hasMore").GetBoolean(); skip = data.GetProperty("nextSkip").GetInt32();
            error.Text = comments.Children.Count == 0 ? "还没有点评，说说这张照片吧。" : "";
        }
        catch (OperationCanceledException) { }
        catch (Exception exception) { if (current == selection && !cancellation.IsCancellationRequested) error.Text = exception.Message; }
        finally { if (loading == cancellation) { busy = false; loading = null; } cancellation.Dispose(); }
    }
    private async Task PostAsync()
    {
        if (busy) return;
        var current = selection; var account = store.SessionVersion;
        var text = await DisplayPromptAsync("照片点评", "说说这张照片", "发表", "取消", maxLength: 2000);
        if (string.IsNullOrWhiteSpace(text) || current != selection || account != store.SessionVersion) return;
        busy = true;
        try { await store.CallAsync(Route, HttpMethod.Post, new { text = text.Trim(), requestId = Guid.NewGuid() }); }
        catch (Exception exception) { error.Text = exception.Message; return; }
        finally { busy = false; }
        if (current == selection && account == store.SessionVersion) await LoadCommentsAsync(true);
    }
}
