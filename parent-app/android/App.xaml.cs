namespace LinkoFamily;

public partial class App : Application
{
    private readonly FamilyStore store = new();

    public App() => InitializeComponent();

    protected override Window CreateWindow(IActivationState? activationState)
        => new(new FamilyPage(store));
}
