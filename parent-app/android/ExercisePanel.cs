using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using Android.Hardware;
using Android.Content;

namespace LinkoFamily;

// Foreground exercise: Android pauses tracking when the window stops.
public sealed partial class ExercisePanel : ContentView
{
    public sealed record ActivityLink(Guid TenantID, Guid Id, string Title);
    private ActivityLink? pendingActivity;
    private Workout? previousWorkout;
    public sealed class Workout
    {
        public Guid Id { get; set; }
        public DateTimeOffset? EndedAt { get; set; }
        public List<WorkoutInterval> Intervals { get; set; } = [];
        public List<WorkoutPoint> Route { get; set; } = [];
        public bool RouteEnabled { get; set; }
        public double? DistanceOverride { get; set; }
        public string? ActivityText { get; set; }
        public JsonElement? SourceRecord { get; set; }
        public Guid SyncId => Id != Guid.Empty ? Id : new Guid(SHA256.HashData(Encoding.UTF8.GetBytes(Kind + "\0" + StartedAt.UtcTicks.ToString(System.Globalization.CultureInfo.InvariantCulture)))[..16]);
        public ActivityLink? Activity { get; set; }
        public string Kind { get; set; } = "散步";
        public DateTimeOffset StartedAt { get; set; }
        public DateTimeOffset? RunningSince { get; set; }
        public DateTimeOffset LastSeen { get; set; }
        public double Seconds { get; set; }
        public int Steps { get; set; }
        public bool HasSteps { get; set; }
        public double? StepLengthMeters { get; set; }
        public string DistanceText => DistanceOverride is { } measured ? $"{measured / 1000:F2} 公里" : HasSteps && StepLengthMeters is { } length
            ? $"约 {Steps * length / 1000:F2} 公里（估算）" : "距离未获取";
        public double Duration => Seconds + (RunningSince is { } start ? Math.Max(0, (DateTimeOffset.UtcNow - start).TotalSeconds) : 0);
    }
    public sealed class Archive
    {
        public List<Guid> Uploaded { get; set; } = [];
        public List<Guid> ActivityShares { get; set; } = [];
        public List<Guid> PendingDeletions { get; set; } = [];
        public Workout? Active { get; set; }
        public List<Workout> History { get; set; } = [];
    }
    private readonly string file;
    private Archive archive = new();
    private readonly Label clock = new() { FontSize = 42, HorizontalTextAlignment = TextAlignment.Center };
    private readonly Label steps = new() { FontSize = 24, HorizontalTextAlignment = TextAlignment.Center };
    private readonly Label distance = new() { FontSize = 28, HorizontalTextAlignment = TextAlignment.Center };
    private readonly Label notice = new() { TextColor = Colors.DarkOrange };
    private readonly VerticalStackLayout body = new() { Spacing = 16 };
    private readonly IDispatcherTimer timer;
    private readonly StepListener listener;
    private readonly SensorManager? sensors;
    private Border? metrics;
    private bool mapMode;
    private string selectedKind = "散步";
    private ExerciseRouteView? routeView;
    private readonly Label syncStatus = MomentStyle.Caption("完成运动后自动同步");
    private readonly ActivityIndicator syncSpinner = new() { Color = MomentStyle.Accent, WidthRequest = 20 };
    private readonly Button syncButton;
    private readonly Label activeState = MomentStyle.Caption("");
    private bool readable = true;
    private bool starting;
    private double stepLengthCm = 70;
    private int lifecycle;
    public ExercisePanel(FamilyStore api, string userID)
    {
        this.api = api; this.userID = userID;
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(userID)));
        file = Path.Combine(FileSystem.AppDataDirectory, $"exercise-{key}.json");
        var root = new Grid { RowDefinitions = new RowDefinitionCollection { new(GridLength.Auto), new(GridLength.Star), new(GridLength.Auto) }, RowSpacing = 10, Padding = new Thickness(16, 12, 16, 0) };
        var title = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
        title.Add(MomentStyle.Title("运动")); title.Add(MomentStyle.Action("⋯", () => _ = More()), 1, 0);
        root.Add(title); root.Add(new ScrollView { Content = body }, 0, 1);
        var footer = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Auto), new(GridLength.Star), new(GridLength.Auto) }, ColumnSpacing = 8, Padding = new Thickness(0, 6) };
        syncStatus.MaxLines = 2; syncStatus.VerticalTextAlignment = TextAlignment.Center;
        syncButton = MomentStyle.Action("同步", () => _ = SyncAsync());
        footer.Add(syncSpinner); footer.Add(syncStatus, 1, 0); footer.Add(syncButton, 2, 0); root.Add(footer, 0, 2); Content = root;
        sensors = Android.App.Application.Context.GetSystemService(Context.SensorService) as SensorManager;
        listener = new StepListener(() => MainThread.BeginInvokeOnMainThread(() =>
        {
            if (archive.Active?.RunningSince is null) return;
            archive.Active.Steps++;
            if (archive.Active.Intervals.LastOrDefault() is { } interval) {
                interval.Steps = (interval.Steps ?? 0) + 1;
                interval.DistanceMeters = interval.Steps * archive.Active.StepLengthMeters;
            }
            Update(); Save();
        }));
        try
        {
            if (File.Exists(file)) archive = JsonSerializer.Deserialize<Archive>(File.ReadAllText(file)) ?? throw new InvalidDataException();
            if (archive.Active is { RunningSince: not null } active)
            {
                active.Seconds += Math.Max(0, (active.LastSeen - active.RunningSince.Value).TotalSeconds);
                active.RunningSince = null;
                if (active.Intervals.LastOrDefault() is { End: null } interval) interval.End = active.LastSeen;
                notice.Text = "上次运动已恢复为暂停状态，请确认后继续。";
                Save();
            }
        }
        catch { readable = false; notice.Text = "运动记录暂时无法读取，原记录已保留。请重新打开应用后重试。"; }
        mapMode = archive.Active?.RouteEnabled == true || archive.Active?.Route.Count > 0;
        timer = Dispatcher.CreateTimer(); timer.Interval = TimeSpan.FromSeconds(1);
        timer.Tick += (_, _) => { Update(); if (archive.Active?.RunningSince != null) Save(); };
        Render();
    }
    public void Suspend() { lifecycle++; Pause(); timer.Stop(); }
    public void LinkActivity(MomentScope scope, string title) {
        if (archive.Active != null) { notice.Text = "请先结束当前运动，再从活动创建运动。"; return; }
        pendingActivity = new(scope.Tenant, scope.Activity, title);
        selectedKind = "徒步"; mapMode = true;
        previousWorkout = archive.History.FirstOrDefault(item => item.Activity?.Id == scope.Activity && item.Activity.TenantID == scope.Tenant);
        Render();
    }
    public void Show() { timer.Start(); Update(); _ = SyncAsync(); }
    private bool Save()
    {
        if (!readable) return false;
        try
        {
            if (archive.Active is { } active) active.LastSeen = DateTimeOffset.UtcNow;
            File.WriteAllText(file + ".tmp", JsonSerializer.Serialize(archive));
            File.Move(file + ".tmp", file, true);
            return true;
        }
        catch (Exception error) { notice.Text = $"记录尚未保存：{error.Message}。请重试保存。"; }
        return false;
    }
    private static Button Action(string text, Action action) => MomentStyle.Action(text, action, true);
    private async Task Start(string kind)
    {
        if (!readable || starting || archive.Active?.RunningSince != null) return;
        starting = true;
        var attempt = lifecycle;
        try
        {
            var granted = !OperatingSystem.IsAndroidVersionAtLeast(29) ||
                await Permissions.RequestAsync<MotionPermission>() == PermissionStatus.Granted;
            if (attempt != lifecycle) return;
            var sensor = sensors?.GetDefaultSensor(SensorType.StepDetector);
            var now = DateTimeOffset.UtcNow;
            archive.Active ??= new Workout { Id = Guid.NewGuid(), Kind = kind, Activity = pendingActivity, StartedAt = now, HasSteps = true, StepLengthMeters = stepLengthCm / 100, RouteEnabled = mapMode };
            pendingActivity = null;
            archive.Active.RunningSince = now;
            var canCount = granted && sensor != null;
            archive.Active.HasSteps &= canCount;
            archive.Active.Intervals.Add(new WorkoutInterval { Start = now, Steps = canCount ? 0 : null, DistanceMeters = canCount ? 0 : null });
            if (!canCount) notice.Text = "未获得运动权限或设备不支持计步；本次可继续计时。";
            else if (sensors?.RegisterListener(listener, sensor, SensorDelay.Normal) != true)
            {
                archive.Active.HasSteps = false; notice.Text = "计步传感器暂不可用，本次可继续计时。";
            }
            Save(); Render(); timer.Start(); if (archive.Active.RouteEnabled || archive.Active.Route.Count > 0) StartLocation();
        }
        catch (Exception error) { notice.Text = $"无法开启计步：{error.Message}"; }
        finally { starting = false; }
    }
    private void Pause()
    {
        locationCancellation?.Cancel(); locationCancellation?.Dispose(); locationCancellation = null;
        sensors?.UnregisterListener(listener);
        if (archive.Active is not { RunningSince: not null } active) return;
        var now = DateTimeOffset.UtcNow;
        active.Seconds = active.Duration; active.RunningSince = null;
        if (active.Intervals.LastOrDefault() is { End: null } interval) interval.End = now;
        Save(); Render();
    }
    private async Task Finish()
    {
        if (archive.Active == null || Window?.Page == null) return;
        if (!await Window.Page.DisplayAlertAsync("结束运动", "结束本次运动并保存记录？", "结束并保存", "继续运动")) return;
        Pause();
        if (archive.Active is { } completed) { completed.EndedAt = DateTimeOffset.UtcNow; if (completed.Intervals.Count > 0 && completed.Intervals[0].Start == completed.StartedAt) completed.Seconds = completed.Intervals.Sum(i => Math.Max(0, ((i.End ?? i.Start) - i.Start).TotalSeconds)); completed.ActivityText = SharedText(completed); archive.History.Insert(0, completed); }
        archive.Active = null; Save(); Render(); await SyncAsync();
    }
    private async Task Continue(Workout item)
    {
        if (archive.Active != null || !readable || starting) return;
        pendingActivity = item.Activity; mapMode = item.RouteEnabled || item.Route.Count > 0;
        // A new segment preserves the completed record and excludes the stopped time.
        await Start(item.Kind);
    }
    internal static string ActivitySummary(string userID, Guid activityID)
    {
        try {
            var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(userID)));
            var path = Path.Combine(FileSystem.AppDataDirectory, $"exercise-{key}.json");
            if (!File.Exists(path)) return "";
            var saved = JsonSerializer.Deserialize<Archive>(File.ReadAllText(path));
            var records = (saved?.History ?? []).Concat(saved?.Active is { } active ? new[] { active } : []).Where(item => item.Activity?.Id == activityID).ToList();
            return string.Join("\n", records.Select(item => $"{item.Kind} · {item.DistanceText} · {TimeSpan.FromSeconds(item.Duration):hh\\:mm\\:ss}"));
        } catch { return "运动记录暂无法读取"; }
    }
    private async Task DeleteRecord(Workout item)
    {
        if (!readable || Window?.Page is not { } page || !archive.History.Contains(item)) return;
        if (!await page.DisplayAlertAsync("删除运动记录", $"删除这条{item.Kind}记录？删除后无法恢复。", "删除", "取消")) return;
        var index = archive.History.IndexOf(item);
        if (index < 0) return;
        archive.History.RemoveAt(index);
        archive.PendingDeletions.Add(item.SyncId);
        if (!Save())
        {
            archive.History.Insert(index, item); archive.PendingDeletions.Remove(item.SyncId);
            notice.Text = "删除失败，运动记录已保留，请稍后重试。";
        }
        Render(); await SyncAsync();
    }
    private void Update()
    {
        clock.Text = ExercisePresentation.Clock(archive.Active?.Duration ?? 0);
        distance.Text = archive.Active?.DistanceText ?? "0.00 公里";
        steps.Text = archive.Active is { HasSteps: true } active ? $"{active.Steps} 步" : "步数待获取";
        altitudeLabel.IsVisible = archive.Active?.RouteEnabled == true || archive.Active?.Route.Count > 0;
        activeState.Text = archive.Active?.RunningSince != null ? "运动中" : "已暂停";
        routeView?.Update(archive.Active?.Route ?? [], archive.Active?.RunningSince != null);
        syncSpinner.IsRunning = syncing; syncSpinner.IsVisible = syncing; syncButton.IsEnabled = !syncing;
    }
    private async Task RetrySensors()
    {
        if (archive.Active is { RunningSince: not null } active) { Pause(); await Start(active.Kind); }
        else { Update(); notice.Text = "继续或开始运动后重新读取计步传感器。"; Render(); }
    }
    private async Task More()
    {
        if (Window?.Page is not { } page) return;
        var choice = await page.DisplayActionSheetAsync("运动设置", "取消", null, "估算步长", "重试读取步数与距离", "重试保存记录", "打开系统设置");
        if (choice == "打开系统设置") AppInfo.ShowSettingsUI();
        else if (choice == "重试保存记录") Save();
        else if (choice == "重试读取步数与距离") await RetrySensors();
        else if (choice == "估算步长") {
            if (archive.Active != null) { await page.DisplayAlertAsync("估算步长", "请在结束本次运动后调整，当前记录保持原步长。", "知道了"); return; }
            var text = await page.DisplayPromptAsync("估算步长", "每步厘米数（20–200），只用于距离估算", "保存", "取消", keyboard: Keyboard.Numeric, initialValue: stepLengthCm.ToString("F0"));
            if (double.TryParse(text, out var value) && double.IsFinite(value) && value is >=20 and <=200) stepLengthCm = value;
        }
    }
    private async Task ShowRoute(Workout item)
    {
        if (Window?.Page is not { } owner) return;
        var map = new ExerciseRouteView(expanded: true); map.Update(item.Route, false, true);
        var page = new ContentPage { Title = item.Kind, BackgroundColor = MomentStyle.Background, SafeAreaEdges = SafeAreaEdges.All, Content = map };
        page.ToolbarItems.Add(new ToolbarItem("完成", null, async () => await owner.Navigation.PopModalAsync()));
        await owner.Navigation.PushModalAsync(new NavigationPage(page));
    }
    private void Render()
    {
        body.Children.Clear();
        if ((archive.Active?.Activity ?? pendingActivity) is { } linked) {
            var association = new VerticalStackLayout { Spacing = 8 };
            association.Add(MomentStyle.Caption("关联活动")); association.Add(MomentStyle.Title(linked.Title, 18));
            if (archive.Active == null) association.Add(MomentStyle.Action("取消关联", () => { pendingActivity = null; previousWorkout = null; Render(); }));
            body.Add(MomentStyle.Card(association));
        }
        var modes = new VerticalStackLayout { Spacing = 10 };
        modes.Add(MomentStyle.Segmented(new[] { "数据", "地图" }, mapMode ? 1 : 0, index => {
            mapMode = index == 1;
            // Like iOS, switching back to data keeps an already enabled route.
            if (mapMode && archive.Active is { } mappedWorkout) { mappedWorkout.RouteEnabled = true; Save(); if (mappedWorkout.RunningSince != null) StartLocation(); }
            Render();
        }));
        if (mapMode) { routeView ??= new ExerciseRouteView(); if (routeView.Parent is Layout oldMap) oldMap.Children.Remove(routeView); modes.Add(routeView); }
        body.Add(MomentStyle.Card(modes));
        body.Add(MomentStyle.Caption(archive.Active?.Kind ?? "开始运动"));
        if (archive.Active is { } active) {
            clock.TextColor = MomentStyle.Ink; distance.TextColor = MomentStyle.Ink;
            metrics ??= MomentStyle.Card(new VerticalStackLayout { Spacing = 12, Padding = new Thickness(4, 18), Children = { clock, distance, steps, altitudeLabel, activeState } });
            if (metrics.Parent is Layout previousMetrics)
                previousMetrics.Children.Remove(metrics);
            body.Add(metrics);
            var actions = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Star) }, ColumnSpacing = 12 };
            actions.Add(Action(active.RunningSince != null ? "暂停" : "继续", () => { if (active.RunningSince != null) Pause(); else _ = Start(active.Kind); }));
            var finish = MomentStyle.Action("结束并保存", () => _ = Finish()); finish.TextColor = Colors.Red; actions.Add(finish, 1, 0); body.Add(actions);
        } else {
            var choice = new Picker { Title = "运动项目", ItemsSource = new[] { "散步", "慢跑", "自由运动", "徒步" }, SelectedItem = selectedKind, TextColor = MomentStyle.Ink };
            choice.SelectedIndexChanged += (_, _) => { if (choice.SelectedItem is string value) selectedKind = value; };
            body.Add(MomentStyle.Card(choice));
            body.Add(Action("开始" + selectedKind, () => _ = Start(selectedKind)));
            choice.SelectedIndexChanged += (_, _) => Render();
            if (previousWorkout is { } previous) body.Add(MomentStyle.Action("继续上次" + previous.Kind, () => _ = Continue(previous)));
        }
        body.Add(MomentStyle.Caption("距离由系统计步估算。地图模式使用 GPS 记录轨迹，暂停时停止定位。安卓切到后台或锁屏时自动暂停，回到应用后可继续。"));
        if (!string.IsNullOrWhiteSpace(notice.Text)) {
            if (notice.Parent is Layout previous) previous.Children.Remove(notice);
            var hints = new VerticalStackLayout { Spacing = 8 }; hints.Add(MomentStyle.Caption("提示")); hints.Add(notice);
            hints.Add(MomentStyle.Action("重试读取步数与距离", () => _ = RetrySensors()));
            hints.Add(MomentStyle.Action("重试保存记录", () => Save())); hints.Add(MomentStyle.Action("打开系统设置", AppInfo.ShowSettingsUI));
            body.Add(MomentStyle.Card(hints));
        }
        body.Add(MomentStyle.Caption("运动记录 · 当地时间"));
        if (archive.History.Count == 0) body.Add(MomentStyle.Card(new VerticalStackLayout { Spacing = 8, Children = { MomentStyle.Title("还没有运动记录", 18), MomentStyle.Caption("完成一次运动后，时长、步数和公里数会保存在这里。") } }));
        foreach (var item in archive.History.OrderByDescending(x => x.StartedAt)) {
            var row = new VerticalStackLayout { Spacing = 8 };
            var top = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto), new(GridLength.Auto) }, ColumnSpacing = 8 };
            top.Add(MomentStyle.Title(item.Kind, 17)); top.Add(MomentStyle.Caption(ExercisePresentation.Clock(item.Seconds)), 1);
            var delete = MomentStyle.Action("删除", () => _ = DeleteRecord(item)); delete.TextColor = Colors.Red; top.Add(delete, 2); row.Add(top);
            var resume = MomentStyle.Action("继续" + item.Kind, () => _ = Continue(item)); resume.IsEnabled = archive.Active == null && !starting; row.Add(resume);
            if (item.Activity is { } linkedActivity) row.Add(MomentStyle.Caption(linkedActivity.Title));
            row.Add(MomentStyle.Title(item.DistanceText, 20));
            if (item.Route.Any(p => p.AltitudeMeters != null)) { var heights = item.Route.Where(p => p.AltitudeMeters != null).Select(p => p.AltitudeMeters!.Value); row.Add(MomentStyle.Caption($"海拔 {heights.Min():F1}–{heights.Max():F1} 米")); }
            if (item.Route.Count > 0) row.Add(MomentStyle.Action("查看轨迹", () => _ = ShowRoute(item)));
            var detail = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) }, ColumnSpacing = 8 };
            detail.Add(MomentStyle.Caption(item.StartedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm"))); detail.Add(MomentStyle.Caption(item.HasSteps ? $"{item.Steps} 步" : "步数未获取"), 1); row.Add(detail);
            body.Add(MomentStyle.Card(row));
        }
        body.Add(MomentStyle.Caption("运动记录及轨迹仅同步到当前账号。离线时保留本机记录并等待重试。"));
        Update();
    }
    private sealed class StepListener(Action step) : Java.Lang.Object, ISensorEventListener
    {
        public void OnAccuracyChanged(Sensor? sensor, SensorStatus accuracy) { }
        public void OnSensorChanged(SensorEvent? e) { if (e?.Sensor?.Type == SensorType.StepDetector) step(); }
    }
    public sealed class MotionPermission : Permissions.BasePlatformPermission
    {
        public override (string androidPermission, bool isRuntime)[] RequiredPermissions =>
            OperatingSystem.IsAndroidVersionAtLeast(29)
                ? [(Android.Manifest.Permission.ActivityRecognition, true)] : [];
    }
}
