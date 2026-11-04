namespace LinkoFamily;

public partial class App : Application
{
    public App() => InitializeComponent();

    private static Page CreateMainPage() => new NavigationPage(new FamilyPage(new FamilyStore()))
    { BarBackgroundColor = MomentStyle.Background, BarTextColor = MomentStyle.Ink };

    protected override Window CreateWindow(IActivationState? activationState)
    {
        if (Preferences.Default.Get(PrivacyPolicyPage.ConsentKey, false))
            return new Window(CreateMainPage());

        Window? window = null;
        var gate = new PrivacyGatePage(() =>
            window!.Page = CreateMainPage());
        window = new Window(gate);
        return window;
    }
}
