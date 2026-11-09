using Android.Content;
using Android.Content.PM;

namespace LinkoFamily;

public sealed class ExternalMapNavigator(string? tencentReferer = null) : IExternalMapNavigator
{
    public IReadOnlyList<MapApp> GetAvailableMaps() => Enum.GetValues<MapApp>().Where(Installed).ToArray();

    private static bool Installed(MapApp app)
    {
        try
        {
#pragma warning disable CA1422
            return Android.App.Application.Context.PackageManager?.GetApplicationInfo(ExternalMapRoutes.Package(app), PackageInfoFlags.MetaData)?.Enabled == true;
#pragma warning restore CA1422
        }
        catch (PackageManager.NameNotFoundException) { return false; }
    }

    public void OpenNavigation(MapApp app, MapDestination destination, NavigationMode mode)
    {
        var uri = ExternalMapRoutes.Build(app, destination, mode, tencentReferer);
        var intent = new Intent(Intent.ActionView, Android.Net.Uri.Parse(uri.AbsoluteUri));
        intent.SetPackage(ExternalMapRoutes.Package(app));
        var activity = Microsoft.Maui.ApplicationModel.Platform.CurrentActivity;
        if (activity == null) throw new InvalidOperationException("应用尚未就绪，请返回页面重试。");
        try { activity.StartActivity(intent); }
        catch (ActivityNotFoundException) { throw new InvalidOperationException("地图未安装、已停用或不支持此导航，请重新选择地图。"); }
        catch (Java.Lang.SecurityException) { throw new InvalidOperationException("系统拒绝启动地图，请检查地图应用状态。"); }
    }

    public static string? ConfiguredTencentReferer => Android.App.Application.Context.PackageManager?
        .GetApplicationInfo(Android.App.Application.Context.PackageName!, PackageInfoFlags.MetaData)?.MetaData?.GetString("LinkoMoment.TencentMapReferer");
}
