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
    public static Border Segmented(IReadOnlyList<string> titles, int selected, Action<int> choose)
    {
        var grid = new Grid { ColumnSpacing = 3 };
        for (var i = 0; i < titles.Count; i++) {
            grid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star)); var index = i;
            var button = new Button { Text = titles[i], FontSize = 14, FontAttributes = FontAttributes.Bold, CornerRadius = 20, MinimumHeightRequest = 36, MinimumWidthRequest = 0, Padding = new Thickness(4, 4), TextColor = Ink, BackgroundColor = i == selected ? Colors.White : Colors.Transparent };
            button.Clicked += (_, _) => choose(index); SemanticProperties.SetDescription(button, titles[i] + (i == selected ? "，已选中" : "")); grid.Add(button, i);
        }
        return new Border { Content = grid, Padding = 3, BackgroundColor = Color.FromArgb("#E8E8ED"), Stroke = Colors.Transparent, StrokeShape = new RoundRectangle { CornerRadius = 24 } };
    }
    public static View MenuRow(string title, string icon, Action action, string detail = "")
    {
        var row = new Grid { ColumnSpacing = 12, ColumnDefinitions = new ColumnDefinitionCollection { new(GridLength.Auto), new(GridLength.Star) } };
        var glyph = Icon(icon, true); glyph.VerticalOptions = LayoutOptions.Center; row.Add(glyph); row.Add(Row(title, detail, action), 1);
        var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => action(); glyph.GestureRecognizers.Add(tap); return row;
    }
    public static View Bowl() => new Microsoft.Maui.Controls.Shapes.Path { Data = (Geometry)new PathGeometryConverter().ConvertFromInvariantString("M8,26 Q12,52 36,52 Q60,52 64,26 Q36,34 8,26 M22,20 Q16,14 23,7 Q27,3 23,0 M36,18 Q30,12 37,6 Q41,2 37,0 M50,16 Q44,10 51,4 Q54,1 51,0")!, Stroke = Colors.DarkOrange, StrokeThickness = 2.5, WidthRequest = 72, HeightRequest = 60, HorizontalOptions = LayoutOptions.Center };
    public static View IconButton(string name, string description, Action action)
    {
        var view = new Grid { WidthRequest = 44, HeightRequest = 44 };
        view.Add(Icon(name, true)); var tap = new TapGestureRecognizer(); tap.Tapped += (_, _) => action(); view.GestureRecognizers.Add(tap);
        SemanticProperties.SetDescription(view, description); return view;
    }
    public static View Icon(string name, bool selected)
    {
        var data = name switch {
            "更多" => "M13,25 A12,12 0 1 0 13,1 A12,12 0 1 0 13,25 M6,13 L7,13 M12,13 L13,13 M18,13 L19,13",
            "推荐" => "M13,1 L15,8 L22,10 L15,12 L13,20 L11,12 L4,10 L11,8 M22,1 L23,4 L26,5 L23,6 L22,9",
            "附近" => "M2,12 L24,2 L17,24 L12,15 Z",
            "常去" => "M13,23 C-9,9 3,-4 13,7 C23,-4 35,9 13,23 Z",
            "随机" => "M4,3 L21,3 L21,22 L4,22 Z M8,8 L9,8 M16,8 L17,8 M12,13 L13,13 M8,18 L9,18 M16,18 L17,18",
            "筛选" => "M2,5 L24,5 M2,13 L24,13 M2,21 L24,21 M7,2 L7,8 M18,10 L18,16 M10,18 L10,24",
            "扫码登录" => "M2,9 L2,2 L9,2 M18,2 L25,2 L25,9 M25,18 L25,25 L18,25 M9,25 L2,25 L2,18 M7,7 L11,7 L11,11 L7,11 Z M17,7 L21,7 L21,11 L17,11 Z M7,17 L11,17 L11,21 L7,21 Z M16,17 L21,21",
            "栏目启用" => "M2,2 L10,2 L10,10 L2,10 Z M16,2 L24,2 L24,10 L16,10 Z M2,16 L10,16 L10,24 L2,24 Z M16,16 L24,16 L24,24 L16,24 Z",
            "修改密码" => "M14,13 A6,6 0 1 0 14,1 A6,6 0 1 0 14,13 M13,13 L13,25 L18,25 L18,21 L16,21 L16,17 L18,17 L18,12",
            "AI 对话" => "M2,3 L23,3 L23,19 L12,19 L6,25 L6,19 L2,19 Z M7,8 L18,8 M7,13 L16,13",
            "连接手表" => "M9,1 L18,1 L18,6 M9,25 L18,25 L18,20 M6,6 L21,6 L21,20 L6,20 Z M13,9 L13,14 L17,14",
            "套餐权益" => "M13,1 L17,4 L22,4 L23,9 L26,13 L23,17 L22,22 L17,23 L13,26 L9,23 L4,22 L3,17 L0,13 L3,9 L4,4 L9,3 Z M7,13 L11,17 L19,8",
            "设置" => "M13,6 A7,7 0 1 0 13,20 A7,7 0 1 0 13,6 M13,0 L13,6 M13,20 L13,26 M0,13 L6,13 M20,13 L26,13 M4,4 L8,8 M18,18 L23,23 M4,23 L8,19 M19,8 L23,4",
            "拍照" => "M2,7 L8,7 L10,3 L17,3 L19,7 L25,7 L25,23 L2,23 Z M13,11 A4,4 0 1 0 13,19 A4,4 0 1 0 13,11",
            "拍视频" => "M2,6 L18,6 L18,22 L2,22 Z M18,11 L25,6 L25,22 L18,17",
            "打卡" => "M13,25 Q2,12 5,6 Q13,-3 21,6 Q24,12 13,25 M13,7 A4,4 0 1 0 13,15 A4,4 0 1 0 13,7",
            "展示样式" => "M2,5 L25,5 M2,13 L25,13 M2,21 L25,21 M8,2 L8,8 M19,10 L19,16 M11,18 L11,24",
            "分享" => "M18,8 A3,3 0 1 0 18,2 A3,3 0 1 0 18,8 M6,16 A3,3 0 1 0 6,10 A3,3 0 1 0 6,16 M18,26 A3,3 0 1 0 18,20 A3,3 0 1 0 18,26 M9,11 L15,7 M9,15 L15,21",
            "干饭" => "M4,2 L4,10 Q4,13 8,13 L8,25 M8,2 L8,10 M12,2 L12,10 Q12,13 8,13 M21,2 Q15,6 16,15 L21,15 L21,25 M21,2 L21,15",
            "带娃" => "M9,10 A3,3 0 1 0 9,4 A3,3 0 1 0 9,10 M3,21 L3,18 Q3,13 9,13 Q15,13 15,18 L15,21 M18,5 Q24,6 20,11 M19,14 Q24,15 24,21",
            "活动" => "M2,4 L23,4 L23,22 L2,22 Z M3,18 L9,12 L14,17 L18,13 L23,18 M16,8 L17,8",
            "消息" => "M4,20 L7,16 L7,10 Q7,3 13,3 Q19,3 19,10 L19,16 L22,20 Z M10,23 Q13,27 16,23",
            "运动" => "M15,5 A2,2 0 1 0 15,1 A2,2 0 1 0 15,5 M13,7 L10,14 L15,18 L14,25 M12,9 L17,13 L22,13 M11,14 L7,22 L3,25 M12,8 L7,9 L4,14",
            _ => "M13,12 A5,5 0 1 0 13,2 A5,5 0 1 0 13,12 M3,25 L3,23 Q3,16 13,16 Q23,16 23,23 L23,25"
        };
        return new Microsoft.Maui.Controls.Shapes.Path { Data = (Geometry)new PathGeometryConverter().ConvertFromInvariantString(data)!, Stroke = new SolidColorBrush(selected ? Accent : Colors.Gray), StrokeThickness = 1.8, WidthRequest = 26, HeightRequest = 27, HorizontalOptions = LayoutOptions.Center };
    }
}
