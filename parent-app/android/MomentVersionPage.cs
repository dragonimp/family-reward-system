namespace LinkoFamily;

public sealed class MomentVersionPage : ContentPage
{
    public MomentVersionPage()
    {
        Title = "版本升级";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        var body = new VerticalStackLayout { Spacing = 16, Padding = new Thickness(20) };
        body.Add(new Label { Text = "当前版本", FontSize = 18, FontAttributes = FontAttributes.Bold });
        body.Add(new Label { Text = $"Linko Moment {AppInfo.Current.VersionString} ({AppInfo.Current.BuildString})" });
        body.Add(new Label { Text = "可在应用市场查看是否有新版本。", TextColor = Colors.DimGray });
        var check = new Button { Text = "前往应用市场检查" };
        check.Clicked += async (_, _) =>
        {
            var packageName = AppInfo.Current.PackageName;
            try { await Launcher.Default.OpenAsync(new Uri($"market://details?id={packageName}")); }
            catch { await Browser.Default.OpenAsync(new Uri($"https://play.google.com/store/apps/details?id={packageName}")); }
        };
        body.Add(check);
        Content = body;
    }
}
