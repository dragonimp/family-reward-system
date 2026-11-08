namespace LinkoFamily;

internal static class MomentLoginScanner
{
    // Only approve the app's existing proof-bound user-center login challenge.
    // Scanning never approves a login automatically and never opens arbitrary QR links.
    public static async Task OpenAsync(Page owner)
    {
        try {
            var choice = await owner.DisplayActionSheetAsync("扫码登录", "取消", null, "拍摄登录二维码", "从相册识别二维码");
            var file = choice == "拍摄登录二维码" ? await MediaPicker.Default.CapturePhotoAsync() : choice == "从相册识别二维码" ? (await MediaPicker.Default.PickPhotosAsync()).FirstOrDefault() : null;
            if (file == null) return;
            string? text;
            try { text = await AndroidQrImage.ReadAsync(file); }
            finally {
                if (choice == "拍摄登录二维码" && Path.IsPathRooted(file.FullPath)) {
                    var path = Path.GetFullPath(file.FullPath); var cache = Path.GetFullPath(FileSystem.CacheDirectory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                    if (path.StartsWith(cache, StringComparison.Ordinal)) try { File.Delete(path); } catch { }
                }
            }
            var url = MomentLoginApproval.Approval(text ?? "") ?? throw new FamilyApiException("未识别到有效的手表登录二维码，请对准二维码重新拍摄。");
            if (await owner.DisplayAlertAsync("确认登录", "即将打开本应用的登录确认页，请核对设备及配对码。", "继续", "取消")) await AgentIdentity.Maui.InAppWebLinks.OpenAsync(url);
        } catch (Exception e) { await owner.DisplayAlertAsync("扫码登录", e is FamilyApiException ? e.Message : "无法读取相机或图片，请检查权限后重试。", "知道了"); }
    }
}
