using Atlas.Releases;
using Atlas.Releases.Maui;
using System.Runtime.InteropServices;
namespace LinkoFamily;
public sealed class MomentVersionPage : ClientUpdatePage
{
    public MomentVersionPage() : base(new Uri("https://home.ai.impx.net/"),
        new ClientUpdateRegistration("family-points", "android",
            RuntimeInformation.OSArchitecture == Architecture.Arm64 ? "arm64" : "x64", AppInfo.Current.VersionString)) { }
}
