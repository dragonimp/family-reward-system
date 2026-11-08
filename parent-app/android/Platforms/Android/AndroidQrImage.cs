using Android.Graphics;
using ZXing;
using ZXing.Common;

namespace LinkoFamily;
internal static class AndroidQrImage
{
    public static async Task<string?> ReadAsync(FileResult file)
    {
        await using var dimensions = await file.OpenReadAsync();
        var bounds = new BitmapFactory.Options { InJustDecodeBounds = true };
        await BitmapFactory.DecodeStreamAsync(dimensions, null, bounds);
        var sample = 1; while (Math.Max(bounds.OutWidth, bounds.OutHeight) / sample > 1600) sample *= 2;
        await using var stream = await file.OpenReadAsync();
        using var bitmap = await BitmapFactory.DecodeStreamAsync(stream, null, new BitmapFactory.Options { InSampleSize = sample });
        if (bitmap == null || bitmap.Width <= 0 || bitmap.Height <= 0) return null;
        return await Task.Run(() => {
            var pixels = new int[bitmap.Width * bitmap.Height]; bitmap.GetPixels(pixels, 0, bitmap.Width, 0, 0, bitmap.Width, bitmap.Height);
            var rgb = new byte[pixels.Length * 3]; for (var i = 0; i < pixels.Length; i++) { rgb[i*3] = (byte)(pixels[i] >> 16); rgb[i*3+1] = (byte)(pixels[i] >> 8); rgb[i*3+2] = (byte)pixels[i]; }
            var reader = new BarcodeReaderGeneric { AutoRotate = true, Options = new DecodingOptions { TryHarder = true, PossibleFormats = new[] { BarcodeFormat.QR_CODE } } };
            return reader.Decode(new RGBLuminanceSource(rgb, bitmap.Width, bitmap.Height, RGBLuminanceSource.BitmapFormat.RGB24))?.Text;
        });
    }
}
