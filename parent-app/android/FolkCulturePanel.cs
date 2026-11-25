using System.Globalization;
using System.Text.Json;

namespace LinkoFamily;

internal sealed class FolkCulturePanel : ContentView
{
    private static readonly string[] Topics = ["事业", "财运", "感情", "健康"];
    private const string Stems = "甲乙丙丁戊己庚辛壬癸";
    private const string Branches = "子丑寅卯辰巳午未申酉戌亥";
    private const string Elements = "木火土金水";
    private static readonly int[] BranchElements = [4, 2, 0, 0, 2, 1, 1, 2, 3, 3, 2, 4];
    private static readonly DateOnly Anchor = new(2000, 1, 1);
    private static readonly Lazy<Task<JsonDocument>> Almanac = new(async () =>
    {
        using var stream = await FileSystem.OpenAppPackageFileAsync("CeceCalendar.json");
        return await JsonDocument.ParseAsync(stream);
    });

    public FolkCulturePanel(string title)
    {
        BackgroundColor = MomentStyle.Background;
        var name = new Entry { Placeholder = "姓名（选填）" };
        var gender = new Picker { Title = "性别", ItemsSource = new[] { "男", "女" } };
        var calendar = new Picker { Title = "历法", ItemsSource = new[] { "公历", "农历" }, SelectedIndex = 0 };
        var year = new Entry { Placeholder = "出生年（1901–2099）", Keyboard = Keyboard.Numeric };
        var month = new Entry { Placeholder = "月", Keyboard = Keyboard.Numeric };
        var day = new Entry { Placeholder = "日", Keyboard = Keyboard.Numeric };
        var leap = new CheckBox();
        var leapRow = new HorizontalStackLayout
        {
            IsVisible = false,
            Children = { leap, new Label { Text = "确认使用农历闰月", VerticalOptions = LayoutOptions.Center } }
        };
        var hour = new Picker { Title = "出生时辰", ItemsSource = Enumerable.Range(0, 12).Select(Period).ToArray() };
        var queryYear = new Entry { Placeholder = "流年查询年份（默认今年）", Keyboard = Keyboard.Numeric };
        var focus = new VerticalStackLayout();
        var choices = Topics.Select(topic => new CheckBox { IsChecked = true }).ToArray();
        for (var index = 0; index < Topics.Length; index++)
        {
            SemanticProperties.SetDescription(choices[index], Topics[index]);
            focus.Add(new HorizontalStackLayout { Children = { choices[index],
                new Label { Text = Topics[index], VerticalOptions = LayoutOptions.Center } } });
        }
        var error = new Label { TextColor = Colors.DarkRed };
        var report = new Label();
        var disclaimer = MomentStyle.Caption("仅供娱乐参考，不作为人生决策依据。");
        disclaimer.IsVisible = false;
        var calculate = new Button { Text = "生成八字与大运报告" };
        calendar.SelectedIndexChanged += (_, _) => leapRow.IsVisible = calendar.SelectedIndex == 1;
        calculate.Clicked += async (_, _) =>
        {
            error.Text = "";
            report.Text = "";
            disclaimer.IsVisible = false;
            if (gender.SelectedIndex < 0 || hour.SelectedIndex < 0 || !int.TryParse(year.Text, out var y)
                || !int.TryParse(month.Text, out var m) || !int.TryParse(day.Text, out var d))
            {
                error.Text = "请补全性别、出生年月日和时辰。";
                return;
            }
            var currentYear = DateTime.Now.Year;
            var selectedYear = currentYear;
            if ((!string.IsNullOrWhiteSpace(queryYear.Text) && !int.TryParse(queryYear.Text, out selectedYear))
                || selectedYear < 1901 || selectedYear > Math.Min(2099, currentYear + 10))
            {
                error.Text = "请输入有效的流年年份，最远可查到当前年份后十年。";
                return;
            }
            var selectedHour = hour.SelectedIndex;
            var isLunar = calendar.SelectedIndex == 1;
            var isLeap = leap.IsChecked;
            var male = gender.SelectedIndex == 0;
            var topics = Topics.Where((_, index) => choices[index].IsChecked).ToHashSet();
            calculate.IsEnabled = false;
            try
            {
                var almanac = (await Almanac.Value).RootElement;
                var heading = string.IsNullOrWhiteSpace(name.Text) ? "八字报告" : $"{name.Text.Trim()}的八字报告";
                report.Text = heading + "\n" + Chart(almanac, y, m, d, selectedHour, isLunar, isLeap, male, selectedYear, topics);
                disclaimer.IsVisible = true;
            }
            catch (ArgumentException failure) { error.Text = failure.Message; }
            catch (Exception failure) when (failure is IOException or JsonException or KeyNotFoundException or InvalidOperationException)
            {
                error.Text = "排盘资料暂不可用。";
            }
            finally { calculate.IsEnabled = true; }
        };

        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = 20, Spacing = 12,
                Children =
                {
                    new Label { Text = title, FontSize = 22, FontAttributes = FontAttributes.Bold },
                    new Label { Text = "八字解析", FontAttributes = FontAttributes.Bold },
                    name, gender, calendar, year, month, day, leapRow, hour,
                    MomentStyle.Caption("按北京时间和时辰中点排盘，子时取 00:00。"),
                    queryYear, MomentStyle.Caption("关注维度"), focus, calculate, error, report, disclaimer
                }
            }
        };
    }

    private static string Chart(JsonElement almanac, int year, int month, int day, int hour, bool lunar, bool leap, bool male, int queryYear, HashSet<string> topics)
    {
        if (year is < 1901 or > 2099 || month is < 1 or > 12 || day is < 1 or > 31)
            throw new ArgumentException("请输入范围内有效的出生日期。");
        DateOnly date;
        if (lunar)
        {
            var rows = almanac.GetProperty("months").GetProperty(year.ToString(CultureInfo.InvariantCulture));
            var row = rows.EnumerateArray().FirstOrDefault(item => item[0].GetInt32() == (leap ? -month : month));
            if (row.ValueKind == JsonValueKind.Undefined || day > row[1].GetInt32())
                throw new ArgumentException("该农历日期不存在，请核对月份、闰月和日。");
            date = DateOnly.ParseExact(row[2].GetString()!, "yyyy-MM-dd", CultureInfo.InvariantCulture).AddDays(day - 1);
        }
        else
        {
            if (day > DateTime.DaysInMonth(year, month)) throw new ArgumentException("该公历日期不存在。");
            date = new DateOnly(year, month, day);
        }
        var dateText = date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var timestamp = FormattableString.Invariant($"{dateText} {hour * 2:D2}:00:00");
        var terms = almanac.GetProperty("terms").GetProperty(date.Year.ToString(CultureInfo.InvariantCulture));
        var boundary = -1;
        for (var i = 0; i < terms.GetArrayLength(); i++)
            if (string.CompareOrdinal(terms[i].GetString(), timestamp) <= 0) boundary = i;
        var yearIndex = Mod(date.Year - 1984 - (boundary < 1 ? 1 : 0), 60);
        var monthOffset = Mod(boundary - 1, 12);
        var monthStem = (yearIndex % 5 * 2 + 2 + monthOffset) % 10;
        var dayIndex = Mod(date.DayNumber - Anchor.DayNumber + 54, 60);
        (int Stem, int Branch)[] pillars = [(yearIndex % 10, yearIndex % 12), (monthStem, (monthOffset + 2) % 12),
            (dayIndex % 10, dayIndex % 12), ((dayIndex % 5 * 2 + hour) % 10, hour)];
        var counts = new int[5];
        foreach (var (stem, branch) in pillars) { counts[stem / 2]++; counts[BranchElements[branch]]++; }
        var names = new[] { "年柱", "月柱", "日柱", "时柱" };
        var columns = string.Join("　", pillars.Select((item, i) => $"{names[i]} {Stems[item.Stem]}{Branches[item.Branch]}"));
        var summary = string.Join("　", counts.Select((count, i) => $"{Elements[i]} {count}"));
        var dayElement = dayIndex % 10 / 2;
        var support = counts[dayElement] - 1 + counts[Mod(dayElement - 1, 5)];
        var strength = support >= 4 ? "表层生扶较多" : support <= 2 ? "表层生扶较少" : "表层生扶居中";
        var result = new List<string>
        {
            $"公历 {dateText} · {Period(hour)}", columns, $"五行分布（表层干支）\n{summary}",
            $"日主 {Stems[dayIndex % 10]}{Elements[dayElement]} · {strength}（简化统计）"
        };
        string[] career = ["安排持续学习的时间", "练习把想法讲清楚", "把长期目标拆成小步骤", "为重要工作订立验收标准", "为变动留出调整空间"];
        result.Add($"事业 · 可从日主的五行意象联想到：{career[dayElement]}。");
        result.Add($"婚姻 · 把日支{Branches[dayIndex % 12]}当作交流话题，聊聊双方如何表达需求和分担责任。");
        result.Add("健康 · 以规律作息、适量活动和休息为日常观察主题。");
        result.Add($"子女 · 可把时支{Branches[hour]}作为亲子交流主题，留意彼此喜欢的陪伴方式。");
        var forward = male == (yearIndex % 2 == 0);
        var termTable = almanac.GetProperty("terms");
        var adjacent = forward
            ? (boundary < 11 ? terms[boundary + 1] : termTable.GetProperty((date.Year + 1).ToString(CultureInfo.InvariantCulture))[0])
            : (boundary >= 0 ? terms[boundary] : termTable.GetProperty((date.Year - 1).ToString(CultureInfo.InvariantCulture))[11]);
        const string timestampFormat = "yyyy-MM-dd HH:mm:ss";
        var term = DateTime.ParseExact(adjacent.GetString()!, timestampFormat, CultureInfo.InvariantCulture);
        var birth = DateTime.ParseExact(timestamp, timestampFormat, CultureInfo.InvariantCulture);
        var minutes = (int)Math.Abs(term.Ticks / TimeSpan.TicksPerMinute - birth.Ticks / TimeSpan.TicksPerMinute);
        var start = birth.AddYears(minutes / 4320).AddMonths(minutes % 4320 / 360)
            .AddDays(minutes % 360 / 12).AddHours(minutes % 12 * 2);
        var annual = Mod(queryYear - 1984, 60);
        result.Add($"流年 {queryYear} {Stems[annual % 10]}{Branches[annual % 12]}（立春起）");
        result.Add(FormattableString.Invariant($"大运{(forward ? "顺排" : "逆排")} · 起运 {start:yyyy-MM-dd}"));
        var index = Math.Max(0, (queryYear - start.Year) / 10);
        for (var step = index; step < index + 4; step++)
        {
            var delta = (step + 1) * (forward ? 1 : -1);
            result.Add($"{start.Year + step * 10}–{start.Year + step * 10 + 9}  {Stems[Mod(monthStem + delta, 10)]}{Branches[Mod(monthOffset + 2 + delta, 12)]}");
        }
        var flowElement = annual % 10 / 2;
        string[] relations = ["同类", "日主相生", "日主相克", "受流年相克", "受流年相生"];
        result.Add($"流年天干属{Elements[flowElement]} · 与日主属于{relations[Mod(flowElement - dayElement, 5)]}的传统关系。");
        string[] tips = [career[flowElement] + "。", "整理收支和近期计划。", "安排一次讨论彼此近况的时间。", "留意作息、运动与休息是否均衡。"];
        for (var topic = 0; topic < Topics.Length; topic++)
            if (topics.Contains(Topics[topic])) result.Add($"流年{Topics[topic]} · {tips[topic]}");
        if (queryYear < start.Year) result.Add("所查年份早于起运。");
        else if ((queryYear - start.Year) % 10 == 0) result.Add("所查年份为起运或换运年份，大运区间按公历年展示。");
        return string.Join("\n", result);
    }

    private static string Period(int index)
    {
        var range = index == 0 ? "23:00–01:00" : $"{index * 2 - 1:D2}:00–{index * 2 + 1:D2}:00";
        return $"{Branches[index]}时（{range}）";
    }

    private static int Mod(int value, int by) => (value % by + by) % by;
}
