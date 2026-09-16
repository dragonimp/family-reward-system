static void Check(bool value) { if (!value) throw new Exception("Pairing assertion failed"); }
var clock = new TestClock();
var sessions = new WatchPairingSessions(clock);
var challenge = (await sessions.Start("https://example.test", "Apple Watch", "watchos"))!;
Check(challenge.Code.Length == 8 && challenge.DeviceToken.Length == 64);
Check(!challenge.VerificationUrl.Contains(challenge.DeviceToken));
Check(challenge.QrModules.Length > 20 && challenge.QrModules.All(row => row.Length == challenge.QrModules.Length));
Check(await sessions.IsPending(challenge.DeviceToken));
Check(!await sessions.IsPending("wrong-token"));
try { await sessions.Approve(challenge.Code, "wrong-parent", 1, _ => throw new UnauthorizedAccessException()); }
catch (UnauthorizedAccessException) { }
Check(await sessions.IsPending(challenge.DeviceToken));
using (var qr = QRCoder.QRCodeGenerator.GenerateQrCode(challenge.VerificationUrl, QRCoder.QRCodeGenerator.ECCLevel.M))
using (var png = new QRCoder.PngByteQRCode(qr)) {
    File.WriteAllBytes("/tmp/family-watch-pairing-qr.png", png.GetGraphic(4));
    File.WriteAllText("/tmp/family-watch-pairing-qr.txt", challenge.VerificationUrl);
}
var writes = 0;
var results = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => sessions.Approve(challenge.Code, "parent", 1, async session => {
    Check(session.TokenHash == WatchPairingSessions.Hash(challenge.DeviceToken));
    await Task.Delay(10); Interlocked.Increment(ref writes); return 42;
})));
Check(writes == 1 && results.All(x => x.DeviceId == 42));
Check(!await sessions.IsPending(challenge.DeviceToken));
Check((await sessions.Approve(challenge.Code, "other", 1, _ => Task.FromResult(99))).Error != null);
Check((await sessions.Approve(challenge.Code, "parent", 2, _ => Task.FromResult(99))).Error != null);
var expired = (await sessions.Start("https://example.test", "Watch", "watchos"))!;
clock.Now = clock.Now.AddMinutes(11);
Check(!await sessions.IsPending(expired.DeviceToken));
Check((await sessions.Approve(expired.Code, "parent", 1, _ => throw new Exception("must not write"))).Error != null);
Console.WriteLine("PASS: private token, QR payload, authorization failure preserves code, concurrent approval once, replay scope, expiry");
sealed class TestClock : TimeProvider { public DateTimeOffset Now = DateTimeOffset.UtcNow; public override DateTimeOffset GetUtcNow() => Now; }
