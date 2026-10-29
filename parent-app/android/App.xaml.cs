namespace LinkoFamily;

public partial class App : Application
{
    public App() => InitializeComponent();

    protected override Window CreateWindow(IActivationState? activationState)
    {
        if (Preferences.Default.Get(PrivacyPolicyPage.ConsentKey, false))
            return new Window(new FamilyPage(new FamilyStore()));

        Window? window = null;
        var gate = new PrivacyGatePage(() =>
            window!.Page = new FamilyPage(new FamilyStore()));
        window = new Window(gate);
        return window;
    }
}
