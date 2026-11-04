using Microsoft.Maui.Controls.Shapes;

namespace LinkoFamily;

internal static class MomentStyle
{
    public static Color Accent => Color.FromArgb("#149EA7");
    public static Color Background => Color.FromArgb("#F2F2F7");
    public static Color Ink => Color.FromArgb("#172126");
    public static Label Title(string text, double size = 30) => new() { Text = text, FontSize = size, FontAttributes = FontAttributes.Bold, TextColor = Ink };
    public static Label Caption(string text) => new() { Text = text, FontSize = 13, TextColor = Color.FromArgb("#787883"), LineBreakMode = LineBreakMode.WordWrap };
    public static Border Card(View content, Thickness? padding = null) => new()
    {
        Content = content, BackgroundColor = Colors.White, Padding = padding ?? new Thickness(16), Stroke = Colors.Transparent,
        StrokeShape = new RoundRectangle { CornerRadius = 18 }
    };
    public static Button Action(string text, Action action, bool primary = false)
    {
        var view = new Button { Text = text, FontSize = 15, CornerRadius = 12, Padding = new Thickness(12, 8), MinimumHeightRequest = 44,
            BackgroundColor = primary ? Accent : Colors.Transparent, TextColor = primary ? Colors.White : Accent };
        view.Clicked += (_, _) => action(); return view;
    }
    public static View Divider() => new BoxView { Color = Color.FromArgb("#E6E6EC"), HeightRequest = 1, Margin = new Thickness(0, 5) };
    public static Grid Row(string title, string detail = "", Action? action = null)
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) }, MinimumHeightRequest = 46, Padding = new Thickness(0, 6) };
        row.Add(new Label { Text = title, FontSize = 17, TextColor = Ink, VerticalTextAlignment = TextAlignment.Center });
        row.Add(new Label { Text = detail + (action == null ? "" : "  ›"), FontSize = 15, TextColor = action == null ? Colors.Gray : Accent, VerticalTextAlignment = TextAlignment.Center }, 1, 0);
        if (action != null) { var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => action(); row.GestureRecognizers.Add(tap); SemanticProperties.SetDescription(row, title); }
        return row;
    }
    public static View IconButton(string name, string description, Action action)
    {
        var view = new Grid { WidthRequest = 44, HeightRequest = 44 };
        view.Add(Icon(name, true)); var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => action(); view.GestureRecognizers.Add(tap);
        SemanticProperties.SetDescription(view, description); return view;
    }
    public static View Icon(string name, bool selected)
    {
        var data = name switch {
            "成长" => "M9,10 A3,3 0 1 0 9,4 A3,3 0 1 0 9,10 M3,21 L3,18 Q3,13 9,13 Q15,13 15,18 L15,21 M18,5 Q24,6 20,11 M19,14 Q24,15 24,21",
            "活动" => "M2,4 L23,4 L23,22 L2,22 Z M3,18 L9,12 L14,17 L18,13 L23,18 M16,8 L17,8",
            "消息" => "M4,20 L7,16 L7,10 Q7,3 13,3 Q19,3 19,10 L19,16 L22,20 Z M10,23 Q13,27 16,23",
            "运动" => "M15,5 A2,2 0 1 0 15,1 A2,2 0 1 0 15,5 M13,7 L10,14 L15,18 L14,25 M12,9 L17,13 L22,13 M11,14 L7,22 L3,25 M12,8 L7,9 L4,14",
            _ => "M13,12 A5,5 0 1 0 13,2 A5,5 0 1 0 13,12 M3,25 L3,23 Q3,16 13,16 Q23,16 23,23 L23,25"
        };
        return new Microsoft.Maui.Controls.Shapes.Path { Data = (Geometry)new PathGeometryConverter().ConvertFromInvariantString(data)!, Stroke = new SolidColorBrush(selected ? Accent : Colors.Gray), StrokeThickness = 1.8, WidthRequest = 26, HeightRequest = 27, HorizontalOptions = LayoutOptions.Center };
    }
}
