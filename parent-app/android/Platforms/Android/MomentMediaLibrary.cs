using Android.Content;
using Android.OS;
using Android.Provider;

namespace LinkoFamily;

internal static class MomentMediaLibrary
{
    public static async Task SaveAsync(string file, string contentType, string name, CancellationToken ct)
    {
        if (!OperatingSystem.IsAndroidVersionAtLeast(29))
        {
            // Older Android requires user-selected storage; the system file share
            // exposes the actual original without requesting broad library access.
            await Share.Default.RequestAsync(new ShareFileRequest("保存原文件", new ShareFile(file, contentType)));
            return;
        }
        var resolver = Android.App.Application.Context.ContentResolver!;
        var video = contentType.StartsWith("video/", StringComparison.Ordinal);
        var collection = video ? MediaStore.Video.Media.ExternalContentUri! : MediaStore.Images.Media.ExternalContentUri!;
        using var values = new ContentValues();
        values.Put(MediaStore.IMediaColumns.DisplayName, string.IsNullOrWhiteSpace(Path.GetFileName(name)) ? Path.GetFileName(file) : Path.GetFileName(name));
        values.Put(MediaStore.IMediaColumns.MimeType, contentType);
        values.Put(MediaStore.IMediaColumns.RelativePath, (video ? Android.OS.Environment.DirectoryMovies : Android.OS.Environment.DirectoryPictures) + "/Linko Moment");
        values.Put(MediaStore.IMediaColumns.IsPending, 1);
        var uri = resolver.Insert(collection, values) ?? throw new IOException("无法创建相册文件。");
        try
        {
            await using (var input = File.OpenRead(file))
            await using (var output = resolver.OpenOutputStream(uri) ?? throw new IOException("无法写入相册。"))
                await input.CopyToAsync(output, ct);
            ct.ThrowIfCancellationRequested();
            using var published = new ContentValues(); published.Put(MediaStore.IMediaColumns.IsPending, 0);
            if (resolver.Update(uri, published, null, null) != 1) throw new IOException("保存未完成。");
        }
        catch { resolver.Delete(uri, null, null); throw; }
    }
}
