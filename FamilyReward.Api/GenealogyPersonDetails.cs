using System.Text.Json.Nodes;

internal sealed record GenealogyPersonDetails(string Gender, short? BirthYear, short? BirthMonth, short? BirthDay,
    bool GenderProvided, bool BirthProvided);

internal static class GenealogyPersonDetailsParser
{
    public static bool TryRead(JsonObject body, out GenealogyPersonDetails details, out string error)
    {
        details = new("", null, null, null, false, false);
        error = "性别或生日格式无效";
        var genderProvided = body.ContainsKey("gender");
        var birthProvided = body.ContainsKey("birthYear") || body.ContainsKey("birthMonth") || body.ContainsKey("birthDay");
        var gender = body["gender"]?.ToString().Trim() ?? "";
        if (gender is not ("" or "male" or "female" or "other")) return false;
        if (!ReadPart(body, "birthYear", 9999, out var year)
            || !ReadPart(body, "birthMonth", 12, out var month)
            || !ReadPart(body, "birthDay", 31, out var day)) return false;
        if (month.HasValue && !year.HasValue || day.HasValue && !month.HasValue) return false;
        if (day.HasValue && day > DateTime.DaysInMonth(year!.Value, month!.Value)) return false;
        details = new(gender, year, month, day, genderProvided, birthProvided);
        error = "";
        return true;
    }

    private static bool ReadPart(JsonObject body, string key, int maximum, out short? value)
    {
        value = null;
        var text = body[key]?.ToString().Trim();
        if (string.IsNullOrEmpty(text)) return true;
        if (!short.TryParse(text, out var number) || number < 1 || number > maximum) return false;
        value = number;
        return true;
    }
}
