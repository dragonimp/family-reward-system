using System.Globalization;
using System.Text.Json;

namespace LinkoFamily;

public readonly record struct MomentRecord(JsonElement Data)
{
    public string Text(string key) => Data.ValueKind == JsonValueKind.Object && Data.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
    public bool Flag(string key) => Data.ValueKind == JsonValueKind.Object && Data.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.True;
    public double? Number(string key) => Data.ValueKind == JsonValueKind.Object && Data.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number) && double.IsFinite(number) ? number : null;
    public Guid? GuidValue(string key) => Guid.TryParseExact(Text(key), "D", out var id) && id != Guid.Empty ? id : null;
    public Guid Id => GuidValue("id") ?? throw new FamilyApiException("活动数据中的标识无效，请刷新后重试。");
    public DateTimeOffset Created => MomentDates.TryInstant(Text("createdAt"), out var date) ? date : DateTimeOffset.MinValue;
    public Guid Tenant(Guid space)
    {
        foreach (var field in new[] { "sourceTenantId", "tenantId" })
        {
            if (Text(field).Length == 0) continue;
            return GuidValue(field) ?? throw new FamilyApiException("活动来源空间标识无效。");
        }
        return space != Guid.Empty ? space : throw new FamilyApiException("活动来源空间未提供。");
    }
    public static List<MomentRecord> List(JsonElement data)
    {
        if (data.ValueKind != JsonValueKind.Array) throw new FamilyApiException("活动列表格式无效，请重试。");
        var rows = data.EnumerateArray().Select(value => new MomentRecord(value.Clone())).ToList();
        var identities = new HashSet<Guid>();
        foreach (var row in rows) if (!identities.Add(row.Id)) throw new FamilyApiException("活动数据存在重复标识，请联系维护人员核对。");
        return rows;
    }
}

public static class MomentDates
{
    public static bool TryInstant(string text, out DateTimeOffset value)
    {
        value = default;
        return text.Length > 10 && (text.EndsWith("Z", StringComparison.OrdinalIgnoreCase) ||
            System.Text.RegularExpressions.Regex.IsMatch(text, @"[+-]\d{2}:\d{2}$")) &&
            DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.None, out value);
    }
    public static DateOnly? ActivityDate(MomentRecord record, TimeZoneInfo? zone = null)
    {
        var value = record.Text("startsAt");
        if (DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day)) return day;
        if (!TryInstant(value, out var instant) && !TryInstant(record.Text("createdAt"), out instant)) return null;
        return DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(instant, zone ?? TimeZoneInfo.Local).DateTime);
    }
    public static string ActivityLabel(MomentRecord record) => ActivityDate(record) is { } date ? $"{(record.Text("startsAt").Length == 0 ? "创建于" : "活动日期")} {date.ToString("d", CultureInfo.CurrentCulture)}" : "日期未设置";
    public static string LocalTime(MomentRecord record) => record.Created == DateTimeOffset.MinValue ? "" : record.Created.ToLocalTime().ToString("g", CultureInfo.CurrentCulture) + "（当地时间）";
    public static string StartOfDay(DateTime day) => new DateTimeOffset(DateTime.SpecifyKind(day.Date, DateTimeKind.Unspecified), TimeZoneInfo.Local.GetUtcOffset(day.Date)).ToString("O", CultureInfo.InvariantCulture);
}

public readonly record struct MomentScope
{
    public Guid Tenant { get; }
    public Guid Activity { get; }
    public MomentScope(Guid tenant, Guid activity)
    {
        if (tenant == Guid.Empty || activity == Guid.Empty) throw new FamilyApiException("活动标识无效。");
        Tenant = tenant; Activity = activity;
    }
    public string Api => $"/api/dear/social/tenants/{Tenant:D}/activities/{Activity:D}";
    public Uri ShareUrl => new($"https://home.ai.impx.net/invite/activity/{Tenant:D}/{Activity:D}");
    public Uri Web => new($"https://happylife.ai.xmkurt.com/dear/spaces/{Tenant:D}/activities/{Activity:D}");
}

public static class MomentLoginApproval
{
    public static Uri? Approval(string text)
    {
        if (!Uri.TryCreate(text, UriKind.Absolute, out var url) || url.Scheme != "https" || !(url.Host is "happylife.ai.impx.net" or "happylife.ai.xmkurt.com") || !url.IsDefaultPort || url.UserInfo.Length != 0 || url.Fragment.Length != 0 || url.AbsolutePath != "/auth/native/approve") return null;
        var parts = url.Query.TrimStart('?').Split('&').Select(x => x.Split('=', 2)).Where(x => x.Length == 2 && x[0] == "id").ToArray();
        if (parts.Length != 1 || parts[0][1].Length != 64 || !parts[0][1].All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f')) return null;
        return url;
    }
}
