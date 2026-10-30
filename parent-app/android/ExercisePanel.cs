using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using Android.Hardware;
using Android.Content;

namespace LinkoFamily;

// Foreground exercise: Android pauses tracking when the window stops.
public sealed class ExercisePanel : ContentView
{
    public sealed class Workout
    {
        public string Kind { get; set; } = "散步";
        public DateTimeOffset StartedAt { get; set; }
        public DateTimeOffset? RunningSince { get; set; }
        public DateTimeOffset LastSeen { get; set; }
        public double Seconds { get; set; }
        public int Steps { get; set; }
        public bool HasSteps { get; set; }
        public double? StepLengthMeters { get; set; }
        public string DistanceText => HasSteps && StepLengthMeters is { } length
            ? $"约 {Steps * length / 1000:F2} 公里（估算）" : "距离未获取";
        public double Duration => Seconds + (RunningSince is { } start ? Math.Max(0, (DateTimeOffset.UtcNow - start).TotalSeconds) : 0);
    }
    public sealed class Archive
    {
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
    private bool readable = true;
    private bool starting;
    private double stepLengthCm = 70;
    private int lifecycle;
    public ExercisePanel(string userID)
    {
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(userID)));
        file = Path.Combine(FileSystem.AppDataDirectory, $"exercise-{key}.json");
        Content = body;
        sensors = Android.App.Application.Context.GetSystemService(Context.SensorService) as SensorManager;
        listener = new StepListener(() => MainThread.BeginInvokeOnMainThread(() =>
        {
            if (archive.Active?.RunningSince is null) return;
            archive.Active.Steps++;
            Update(); Save();
        }));
        try
        {
            if (File.Exists(file)) archive = JsonSerializer.Deserialize<Archive>(File.ReadAllText(file)) ?? throw new InvalidDataException();
            if (archive.Active is { RunningSince: not null } active)
            {
                active.Seconds += Math.Max(0, (active.LastSeen - active.RunningSince.Value).TotalSeconds);
                active.RunningSince = null;
                notice.Text = "上次运动已恢复为暂停状态，请确认后继续。";
                Save();
            }
        }
        catch { readable = false; notice.Text = "运动记录暂时无法读取，原记录已保留。请重新打开应用后重试。"; }
        timer = Dispatcher.CreateTimer(); timer.Interval = TimeSpan.FromSeconds(1);
        timer.Tick += (_, _) => { Update(); if (archive.Active?.RunningSince != null) Save(); };
        Render();
    }
    public void Suspend() { lifecycle++; Pause(); timer.Stop(); }
    public void Show() { timer.Start(); Update(); }
    private void Save()
    {
        if (!readable) return;
        try
        {
            if (archive.Active is { } active) active.LastSeen = DateTimeOffset.UtcNow;
            File.WriteAllText(file + ".tmp", JsonSerializer.Serialize(archive));
            File.Move(file + ".tmp", file, true);
        }
        catch (Exception error) { notice.Text = $"记录尚未保存：{error.Message}。请重试保存。"; }
    }
    private static Button Action(string text, Action action)
    {
        var button = new Button { Text = text, BackgroundColor = Color.FromArgb("#0F766E"), TextColor = Colors.White };
        button.Clicked += (_, _) => action(); return button;
    }
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
            archive.Active ??= new Workout { Kind = kind, StartedAt = now, HasSteps = true, StepLengthMeters = stepLengthCm / 100 };
            archive.Active.RunningSince = now;
            var canCount = granted && sensor != null;
            archive.Active.HasSteps &= canCount;
            if (!canCount) notice.Text = "未获得运动权限或设备不支持计步；本次可继续计时。";
            else if (sensors?.RegisterListener(listener, sensor, SensorDelay.Normal) != true)
            {
                archive.Active.HasSteps = false; notice.Text = "计步传感器暂不可用，本次可继续计时。";
            }
            Save(); Render(); timer.Start();
        }
        catch (Exception error) { notice.Text = $"无法开启计步：{error.Message}"; }
        finally { starting = false; }
    }
    private void Pause()
    {
        sensors?.UnregisterListener(listener);
        if (archive.Active is not { RunningSince: not null } active) return;
        active.Seconds = active.Duration; active.RunningSince = null;
        Save(); Render();
    }
    private async Task Finish()
    {
        if (archive.Active == null || Window?.Page == null) return;
        if (!await Window.Page.DisplayAlertAsync("结束运动", "结束本次运动并保存记录？", "结束并保存", "继续运动")) return;
        Pause();
        if (archive.Active is { } completed) archive.History.Insert(0, completed);
        archive.Active = null; Save(); Render();
    }
    private void Update()
    {
        clock.Text = TimeSpan.FromSeconds(archive.Active?.Duration ?? 0).ToString(@"hh\:mm\:ss");
        distance.Text = archive.Active?.DistanceText ?? "0.00 公里";
        steps.Text = archive.Active is { HasSteps: true } active ? $"{active.Steps} 步" : "计步未启用";
    }
    private void Render()
    {
        body.Children.Clear();
        body.Add(new Label { Text = "运动", FontSize = 27, FontAttributes = FontAttributes.Bold });
        body.Add(new Label { Text = "带上手机，记录一场散步或轻运动。" });
        body.Add(clock); body.Add(distance); body.Add(steps); body.Add(notice);
        if (archive.Active is { } active)
        {
            body.Add(new Label { Text = $"{active.Kind} · {(active.RunningSince != null ? "运动中" : "已暂停")}" });
            body.Add(Action(active.RunningSince != null ? "暂停" : "继续", () => { if (active.RunningSince != null) Pause(); else _ = Start(active.Kind); }));
            body.Add(Action("结束并保存", () => _ = Finish()));
        }
        else
        {
            body.Add(new Label { Text = "估算步长（厘米）" });
            var stride = new Stepper { Minimum = 20, Maximum = 200, Increment = 1, Value = stepLengthCm };
            var strideLabel = new Label { Text = $"{stepLengthCm:F0} 厘米/步" };
            stride.ValueChanged += (_, e) => { stepLengthCm = e.NewValue; strideLabel.Text = $"{stepLengthCm:F0} 厘米/步"; };
            body.Add(stride); body.Add(strideLabel);
            foreach (var kind in new[] { "散步", "慢跑", "自由运动" }) body.Add(Action($"开始{kind}", () => _ = Start(kind)));
        }
        body.Add(new Label { Text = "请保持应用在前台。锁屏或切到后台时自动暂停，回到应用后可继续；暂停期间不计时、不计步、不累计距离。公里数按步数乘本次步长估算，默认 70 厘米/步，可在开始前调整；非 GPS 测距。计步可能稍有延迟。", FontSize = 13 });
        body.Add(Action("重试保存记录", Save));
        body.Add(Action("运动权限设置", AppInfo.ShowSettingsUI));
        body.Add(new Label { Text = "运动记录 · 当地时间", FontSize = 20, FontAttributes = FontAttributes.Bold });
        if (archive.History.Count == 0) body.Add(new Label { Text = "完成一次运动后，时长、步数和估算公里数会保存在这里。" });
        foreach (var item in archive.History)
            body.Add(new Label { Text = $"{item.Kind} · {item.DistanceText} · {item.StartedAt.ToLocalTime():yyyy-MM-dd HH:mm}\n{TimeSpan.FromSeconds(item.Seconds):hh\\:mm\\:ss} · {(item.HasSteps ? $"{item.Steps} 步" : "步数未完整获取")}" });
        body.Add(new Label { Text = "记录按当前账号保存在此手机，暂不跨设备同步。", FontSize = 13 });
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
