using System.Globalization;
using System.Text.Json.Nodes;

namespace LinkoFamily;

// Three-way account merge. Provider IDs are business strings; only actual UUIDs
// (history/circles and the manual: UUID suffix) have case-insensitive identity.
public sealed class DiningSyncConflictException : Exception { public DiningSyncConflictException() : base("存在相同记录标识但内容不同的旧记录，请先核对，原记录已保留。") { } }

public static class DiningSyncMerge
{
    static readonly string[] Lists = ["history", "favorites", "circles", "manualRestaurants"];
    public static JsonObject Empty() => new() { ["history"] = new JsonArray(), ["habits"] = new JsonObject(), ["favorites"] = new JsonArray(), ["circles"] = new JsonArray(), ["manualRestaurants"] = new JsonArray() };
    static string Text(JsonObject row, string key) => row[key]?.GetValue<string>() ?? "";
    static string PlaceId(string value) => value.StartsWith("manual:", StringComparison.Ordinal) && Guid.TryParse(value[7..], out var id) ? "manual:" + id.ToString("D") : value;
    static string Key(string kind, JsonObject row) => kind is "history" or "circles" ? Guid.Parse(Text(row, "id")).ToString("D") : PlaceId(Text(row, "id"));
    static void Place(JsonObject row)
    {
        foreach (var key in new[] { "id", "name", "address", "category", "provider" }) if (row[key] is not JsonValue value || !value.TryGetValue<string>(out var text) || text.Length > 2000) throw new ArgumentException("餐厅信息无效。");
        if (Text(row,"id").Length is < 1 or > 500 || string.IsNullOrWhiteSpace(Text(row,"name"))) throw new ArgumentException("餐厅名称无效。");
        row["id"] = PlaceId(Text(row,"id"));
        row["cost"] ??= null; row["rating"] ??= null;
        Coordinate(row);
        foreach (var field in new[] { "cost", "rating", "distanceMeters" }) if (row[field] is { } number && (!double.TryParse(number.ToString(), CultureInfo.InvariantCulture, out var n) || !double.IsFinite(n) || n < 0)) throw new ArgumentException("餐厅数值无效。");
    }
    static void Coordinate(JsonObject row)
    {
        foreach (var (key,max) in new[] { ("latitude",90), ("longitude",180) }) if (row[key] is not JsonValue v || !v.TryGetValue<double>(out var n) || !double.IsFinite(n) || Math.Abs(n)>max) throw new ArgumentException("位置无效。");
    }
    public static JsonObject Normalize(JsonObject value)
    {
        var result = Empty();
        foreach (var kind in Lists)
        {
            if (value[kind] is null && kind == "manualRestaurants") continue; // legacy iOS optional field
            if (value[kind] is not JsonArray list || list.Count > 10000) throw new ArgumentException("干饭记录格式或数量无效。");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var node in list)
            {
                if (node is not JsonObject source) throw new ArgumentException("记录格式无效。");
                var row = source.DeepClone().AsObject();
                if (kind is "history" or "circles") {
                    if (!Guid.TryParse(Text(row,"id"),out var id) || id==Guid.Empty) throw new ArgumentException("记录标识无效。");
                    row["id"] = id.ToString("D");
                }
                if (kind == "history") {
                    if (row["place"] is not JsonObject place) throw new ArgumentException("餐厅缺失。"); Place(place);
                    if (Text(row,"mood") is not ("automatic" or "familiar" or "fresh" or "budget" or "treat" or "spicy")) throw new ArgumentException("心情无效。");
                    foreach (var field in new[] { "selectedAt", "eatenAt" }) {
                        if (field=="eatenAt" && row[field] is null) continue;
                        var text=Text(row,field);
                        if (!System.Text.RegularExpressions.Regex.IsMatch(text,@"(?:[zZ]|[+-]\d{2}:\d{2})$") || !DateTimeOffset.TryParse(text,CultureInfo.InvariantCulture,DateTimeStyles.None,out var instant)) throw new ArgumentException("时间必须包含时区。");
                        row[field]=instant.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'",CultureInfo.InvariantCulture);
                    }
                    if (row["checkedIn"] is JsonValue flag && !flag.TryGetValue<bool>(out _)) throw new ArgumentException("打卡状态无效。");
                    row["checkedIn"]=row["checkedIn"]?.GetValue<bool>()??false;
                    row["eatenAt"] ??= null;
                    var restaurantType=Text(row,"restaurantType").Trim();if(restaurantType.Length>100)throw new ArgumentException("餐厅类型过长。");row["restaurantType"]=restaurantType.Length==0?null:restaurantType;
                } else if (kind == "circles") { Coordinate(row); if (string.IsNullOrWhiteSpace(Text(row,"name")) || Text(row,"name").Length>100) throw new ArgumentException("生活圈无效。"); }
                else Place(row);
                if (!seen.Add(Key(kind,row))) throw new ArgumentException("存在语义重复标识，请先核对记录。");
                result[kind]!.AsArray().Add(row);
            }
        }
        if (value["habits"] is not JsonObject habits || habits.Count>10000) throw new ArgumentException("偏好格式无效。");
        foreach (var pair in habits) {
            var id=PlaceId(pair.Key); if (id.Length is <1 or >500 || result["habits"]![id] is not null || pair.Value is not JsonObject counts) throw new ArgumentException("偏好标识无效。");
            var target=new JsonObject();
            foreach(var key in new[]{"selected","eaten","skipped","checkIns"}) {
                var count=counts[key] is null ? 0 : counts[key]!.GetValue<int>(); if(count<0 || count>100000000)throw new ArgumentException("偏好计数无效。");target[key]=count;
            }
            result["habits"]![id]=target;
        }
        return result;
    }
    static Dictionary<string,JsonObject> Rows(JsonObject value,string kind) => value[kind]!.AsArray().Select(x=>x!.AsObject()).ToDictionary(x=>Key(kind,x),StringComparer.Ordinal);
    public static JsonObject Merge(JsonObject remote, JsonObject? baseline, JsonObject local, JsonObject tombstones)
    {
        var result=remote.DeepClone().AsObject();
        foreach(var kind in Lists) {
            var prior=baseline is null ? new Dictionary<string,JsonObject>(StringComparer.Ordinal) : Rows(baseline,kind);
            var edits=Rows(local,kind);var current=Rows(remote,kind);
            var deleted=tombstones[kind] as JsonObject ?? new JsonObject();tombstones[kind]=deleted.Parent is null?deleted:deleted.DeepClone();deleted=tombstones[kind]!.AsObject();
            if(baseline is not null) foreach(var key in prior.Keys.Except(edits.Keys)) {current.Remove(key);deleted[key]=true;}
            foreach(var pair in edits) {
                if(prior.TryGetValue(pair.Key,out var before) && JsonNode.DeepEquals(before,pair.Value))continue;
                if(baseline is null && deleted.ContainsKey(pair.Key))continue;
                if(baseline is null && current.TryGetValue(pair.Key,out var imported)) {
                    if(kind is "history" or "circles" && !JsonNode.DeepEquals(imported,pair.Value))throw new DiningSyncConflictException();
                    continue;
                }
                current[pair.Key]=pair.Value;deleted.Remove(pair.Key);
            }
            result[kind]=new JsonArray(current.OrderBy(p=>p.Key,StringComparer.Ordinal).Select(p=>(JsonNode)p.Value.DeepClone()).ToArray());
        }
        var counters=result["habits"]!.AsObject();
        foreach(var pair in local["habits"]!.AsObject()) {
            var current=counters[pair.Key] as JsonObject ?? new JsonObject();if(current.Parent is null)counters[pair.Key]=current;
            foreach(var key in new[]{"selected","eaten","skipped","checkIns"}) {
                var next=pair.Value![key]!.GetValue<int>();var old=baseline?["habits"]?[pair.Key]?[key]?.GetValue<int>()??0;var count=current[key]?.GetValue<int>()??0;
                current[key]=baseline is null ? Math.Max(count,next) : checked(count+Math.Max(0,next-old));
            }
        }
        foreach (var group in result["history"]!.AsArray().Select(x=>x!.AsObject()).GroupBy(x=>Text(x["place"]!.AsObject(),"id"))) {
            var counts=counters[group.Key] as JsonObject;
            if(counts is null){counts=new JsonObject{["selected"]=0,["eaten"]=0,["skipped"]=0,["checkIns"]=0};counters[group.Key]=counts;}
            counts["checkIns"]=Math.Max(counts["checkIns"]!.GetValue<int>(),group.Count(x=>x["checkedIn"]?.GetValue<bool>()==true));
            counts["eaten"]=Math.Max(counts["eaten"]!.GetValue<int>(),group.Count(x=>x["checkedIn"]?.GetValue<bool>()!=true&&x["eatenAt"] is not null));
        }
        // Sorting is presentation-neutral and keeps stable snapshots on both platforms.
        result["history"]=new JsonArray(result["history"]!.AsArray().OrderByDescending(x=>x!["selectedAt"]!.GetValue<string>(),StringComparer.Ordinal).ThenBy(x=>x!["id"]!.GetValue<string>(),StringComparer.Ordinal).Select(x=>x!.DeepClone()).ToArray());
        return Normalize(result);
    }
}
