namespace LinkoFamily;

public sealed class MomentAboutPage : ContentPage
{
    public MomentAboutPage(FamilyStore store)
    {
        Title = "关于我们";
        BackgroundColor = Color.FromArgb("#F4F8F7");
        var content = new VerticalStackLayout { Padding = 20, Spacing = 16 };
        content.Add(MomentStyle.Caption("应用介绍"));
        content.Add(new Label { Text = "Linko Moment 帮助家庭记录生活、分享照片与活动，并一起管理孩子的成长和日常事务。" });
        content.Add(MomentStyle.Caption("版本信息"));
        content.Add(new Label { Text = $"当前版本：{AppInfo.Current.VersionString}（{AppInfo.Current.BuildString}）" });
        content.Add(MomentStyle.Row("版本升级", action: () => _ = Navigation.PushAsync(new MomentVersionPage())));
        content.Add(MomentStyle.Caption("APP 备案号"));
        content.Add(MomentStyle.Row("闽ICP备2024055146号-4A", action: () =>
            _ = AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri("https://beian.miit.gov.cn/"))));
        content.Add(MomentStyle.Row("同行共创", action: () => _ = Navigation.PushAsync(new AtlasInformationPage(true))));
        content.Add(MomentStyle.Row("测试邀请", action: () => _ = Navigation.PushAsync(new TestInvitationPage())));
        content.Add(MomentStyle.Row("意见反馈", action: () => _ = Navigation.PushAsync(new FeedbackWallPage(store))));
        Content = new ScrollView { Content = content };
    }
}
