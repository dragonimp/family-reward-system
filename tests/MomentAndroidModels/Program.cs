using System.Text.Json;
using LinkoFamily;
static MomentRecord Row(string json) => new(JsonDocument.Parse(json).RootElement.Clone());
static void Check(bool ok, string label) { if (!ok) throw new Exception(label); var shareScope = new MomentScope(Guid.NewGuid(), Guid.NewGuid());
if (shareScope.ShareUrl.AbsolutePath != $"/invite/activity/{shareScope.Tenant:D}/{shareScope.Activity:D}" ||
    shareScope.Web.AbsolutePath != $"/dear/spaces/{shareScope.Tenant:D}/activities/{shareScope.Activity:D}")
    throw new InvalidOperationException("Activity sharing must open the public introduction and preserve the protected navigation route.");
Console.WriteLine("PASS " + label); }
var id = Guid.Parse("D2FD4DAD-93B1-4FAE-A057-61DBE0559213");
foreach (var value in new[] { id.ToString("D"), id.ToString("D").ToUpperInvariant(), "D2fD4Dad-93B1-4FAe-A057-61dbe0559213" })
    Check(Row($$"""{"id":"{{value}}"}""").Id == id, "GUID case variant has identical identity");
try { MomentRecord.List(JsonDocument.Parse($$"""[{"id":"{{id:D}}"},{"id":"{{id.ToString("D").ToUpperInvariant()}}"}]""").RootElement); throw new Exception("duplicate accepted"); }
catch (FamilyApiException) { Console.WriteLine("PASS semantic duplicate GUID is reported instead of silently merged"); }
var la = TimeZoneInfo.FindSystemTimeZoneById("America/Los_Angeles"); var tokyo = TimeZoneInfo.FindSystemTimeZoneById("Asia/Tokyo");
var instant = Row("""{"startsAt":"2026-11-01T01:00:00Z"}""");
Check(MomentDates.ActivityDate(instant, la) == new DateOnly(2026, 10, 31), "activity instant uses client time zone");
Check(MomentDates.ActivityDate(instant, tokyo) == new DateOnly(2026, 11, 1), "different client time zone changes activity date");
foreach (var zone in new[] { la, tokyo, TimeZoneInfo.Utc }) Check(MomentDates.ActivityDate(Row("""{"startsAt":"2026-11-01"}"""), zone) == new DateOnly(2026, 11, 1), "calendar-only date never shifts");
Check(MomentDates.ActivityDate(Row("""{"startsAt":"2026-02-30"}""")) == null, "invalid calendar date rejected");
Check(!MomentDates.TryInstant("2026-11-01T12:00:00", out _), "timestamp without zone is not interpreted as server or client local time");
Check(Row("""{"altitudeMeters":null}""").Number("altitudeMeters") == null, "absent altitude is not displayed as sea level");
Check(Row("""{"altitudeMeters":0}""").Number("altitudeMeters") == 0, "real zero altitude is retained");
var scope = new MomentScope(id, id); Check(scope.Api.Contains(id.ToString("D")) && scope.Web.IsAbsoluteUri, "typed scope produces canonical public GUID routes");
try { _ = Row("""{"sourceTenantId":"not-a-guid"}""").Tenant(id); throw new Exception("invalid scope accepted"); } catch (FamilyApiException) { Console.WriteLine("PASS malformed explicit tenant cannot fall back to another space"); }
var qr = "https://happylife.ai.impx.net/auth/native/approve?id=" + new string('a',64);
Check(MomentLoginApproval.Approval(qr) != null, "official login QR reaches existing approval flow");
foreach (var bad in new[] { qr.Replace("https:","http:"), qr.Replace("happylife.ai.impx.net","attacker.example"), qr.Replace("/approve?","/other?"), qr.Replace(new string('a',64),new string('A',64)), qr + "&id=" + new string('b',64), qr + "#fragment" }) Check(MomentLoginApproval.Approval(bad) == null, "unsafe or ambiguous login QR is rejected");
Console.WriteLine("Android Moment model checks completed");

var expiry = DateTimeOffset.UtcNow.AddHours(1).ToUnixTimeMilliseconds();
string Request(string transport = "connect-datachannel-v1", double length = 42, string? sha = null, long? expires = null) => System.Text.Json.JsonSerializer.Serialize(new { id = id.ToString("D").ToUpperInvariant(), transport, length, sha256 = sha ?? new string('A', 64), expiresAt = expires ?? expiry });
var manifest = MomentOriginalContract.Manifest(Row(Request()));
Check(manifest.Length == 42 && manifest.Sha256 == new string('A', 64), "native original manifest accepts valid identity and uppercase SHA");
foreach (var invalid in new[] { Request(transport: "legacy"), Request(length: 0), Request(length: 0.5), Request(length: 524288001), Request(sha: new string('z', 64)), Request(expires: 1) }) {
    try { MomentOriginalContract.Manifest(Row(invalid)); throw new Exception("invalid original grant accepted"); }
    catch (FamilyApiException) { Console.WriteLine("PASS invalid original manifest rejected"); }
}
Check(MomentOriginalContract.Suffix("image/heic") == ".heic" && MomentOriginalContract.Suffix("video/quicktime") == ".mov", "original file MIME keeps the original format");
try { MomentOriginalContract.Suffix("text/html"); throw new Exception("non-media accepted"); } catch (FamilyApiException) { Console.WriteLine("PASS non-media original rejected"); }
