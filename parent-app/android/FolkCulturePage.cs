using System.Globalization;

namespace LinkoFamily;

internal sealed class FolkCulturePage : ContentPage
{
    private static readonly string[] Animals = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"];
    private static readonly string[] Themes = ["播种与生长", "灯火与节庆", "土地与收成", "金石与手作", "河流与雨水"];

    public FolkCulturePage()
    {
        Title = "民俗工具";
        BackgroundColor = MomentStyle.Background;
        var date = new DatePicker { Date = DateTime.Today, MinimumDate = new(1902, 1, 1), MaximumDate = new(2099, 12, 31) };
        var lunarSummary = new Label();
        var family = new Entry { Placeholder = "姓的康熙笔画，按字用空格分隔" };
        var name = new Entry { Placeholder = "名的康熙笔画，按字用空格分隔" };
        var grids = new Label();
        var first = new Picker { Title = "甲方生肖", ItemsSource = Animals, SelectedIndex = 0 };
        var second = new Picker { Title = "乙方生肖", ItemsSource = Animals, SelectedIndex = 0 };
        var pairing = new Label();

        void ShowDate()
        {
            var calendar = new ChineseLunisolarCalendar();
            if (date.Date is not DateTime selected) return;
            var year = calendar.GetSexagenaryYear(selected) - 1;
            var month = calendar.GetMonth(selected);
            var leap = calendar.GetLeapMonth(calendar.GetYear(selected));
            var prefix = leap == month ? "闰" : "";
            if (leap > 0 && month >= leap) month--;
            const string stems = "甲乙丙丁戊己庚辛壬癸";
            const string branches = "子丑寅卯辰巳午未申酉戌亥";
            lunarSummary.Text = $"农历 {stems[year % 10]}{branches[year % 12]}年 {prefix}{month}月{calendar.GetDayOfMonth(selected)}日（春节换年）\n生肖：{Animals[year % 12]}\n民俗主题：{Themes[year % 10 / 2]}";
        }
        void ShowGrids()
        {
            var f = ReadStrokes(family.Text);
            var g = ReadStrokes(name.Text);
            if (f.Length == 0 || g.Length == 0) { grids.Text = ""; return; }
            int fp = f.Length == 1 ? 1 : 0, gp = g.Length == 1 ? 1 : 0;
            grids.Text = $"天格 {f.Sum() + fp}　人格 {f[^1] + g[0]}　地格 {g.Sum() + gp}\n外格 {f.Sum() - f[^1] + g.Sum() - g[0] + fp + gp}　总格 {f.Sum() + g.Sum()}";
        }
        void ShowPairing()
        {
            var a = first.SelectedIndex;
            var b = second.SelectedIndex;
            if (a < 0 || b < 0) return;
            pairing.Text = (Math.Min(a, b), Math.Max(a, b)) switch
            {
                (0, 1) or (2, 11) or (3, 10) or (4, 9) or (5, 8) or (6, 7) => "传统生肖六合",
                _ when Math.Abs(a - b) == 6 => "传统生肖六冲",
                _ when a == b => "生肖相同",
                _ when a % 4 == b % 4 => "同属传统生肖三合组",
                _ => "民俗合参：其他组合"
            };
        }

        date.DateSelected += (_, _) => ShowDate();
        family.TextChanged += (_, _) => ShowGrids();
        name.TextChanged += (_, _) => ShowGrids();
        first.SelectedIndexChanged += (_, _) => ShowPairing();
        second.SelectedIndexChanged += (_, _) => ShowPairing();
        ShowDate();
        ShowPairing();

        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = 20, Spacing = 12,
                Children =
                {
                    new Label { Text = "农历与流年趣味", FontAttributes = FontAttributes.Bold },
                    date, lunarSummary, MomentStyle.Caption("仅供民俗娱乐"),
                    new Label { Text = "姓名五格", FontAttributes = FontAttributes.Bold },
                    family, name, grids, MomentStyle.Caption("姓和名各支持一至两个字，每字 1–60 画。仅供取名文化参考。"),
                    new Label { Text = "生肖趣味合参", FontAttributes = FontAttributes.Bold },
                    first, second, pairing, MomentStyle.Caption("仅供民俗游戏，不能作为婚恋依据。")
                }
            }
        };
    }

    private static int[] ReadStrokes(string? input)
    {
        var parts = (input ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length is < 1 or > 2) return [];
        var result = new int[parts.Length];
        for (var index = 0; index < parts.Length; index++)
        {
            if (!int.TryParse(parts[index], out result[index]) || result[index] is < 1 or > 60) return [];
        }
        return result;
    }
}
