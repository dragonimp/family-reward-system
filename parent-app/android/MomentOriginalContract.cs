using MyVnc.Realtime.Client;
namespace LinkoFamily;

internal static class MomentOriginalContract
{
    internal static RealtimeFileManifest Manifest(MomentRecord row)
    {
        var length = row.Number("length"); var expiry = row.Number("expiresAt"); var sha = row.Text("sha256");
        if (row.Id == Guid.Empty || row.Text("transport") != "connect-datachannel-v1" || length is not > 0 || length > 524288000 || length != Math.Truncate(length.Value) || expiry is not > 0 || expiry > 253402300799999 || sha.Length != 64 || !sha.All(Uri.IsHexDigit))
            throw new FamilyApiException("原文件请求回执无效。");
        var expiresAt = DateTimeOffset.FromUnixTimeMilliseconds((long)expiry.Value);
        if (expiresAt <= DateTimeOffset.UtcNow) throw new FamilyApiException("原文件请求已过期，请重试。");
        return new((long)length.Value, sha, expiresAt);
    }
    internal static string Suffix(string contentType) => contentType switch {
        "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp", "image/heic" => ".heic", "image/heif" => ".heif",
        "video/mp4" => ".mp4", "video/quicktime" => ".mov", _ => throw new FamilyApiException("暂不支持此原文件格式。") };
}
