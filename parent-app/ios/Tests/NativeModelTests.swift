import Foundation
@main struct NativeModelTests {
    static func require(_ condition: @autoclosure () throws -> Bool) throws { let result = try condition(); precondition(result) }
    static func main() throws {
        let draftBase = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ATLAS_BUILD_WORK"] ?? NSTemporaryDirectory()).appendingPathComponent("draft-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: draftBase) }
        try FileManager.default.createDirectory(at: draftBase, withIntermediateDirectories: true)
        let original = draftBase.appendingPathComponent("capture.heic")
        let bytes = Data([1, 3, 5, 7]); try bytes.write(to: original)
        let drafts = try MomentDraftStore(base: draftBase, account: "account-a")
        var entry = MomentLocalDraft(tenant: UUID(), activity: UUID(), kind: "media", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        entry.displayName = "capture.heic"; entry.contentType = "image/heic"
        let saved = try drafts.enqueue(entry, media: original)
        let restored = try MomentDraftStore(base: draftBase, account: "account-a").entries()
        precondition(restored.count == 1 && restored[0].id == entry.id && restored[0].createdAt == entry.createdAt)
        try require(Data(contentsOf: drafts.file(saved)!) == bytes)
        try require(MomentDraftStore(base: draftBase, account: "account-b").entries().isEmpty)
        var failed = saved; failed.lastError = "offline"; try drafts.save(failed)
        try require(drafts.entries().first?.id == saved.id)
        try require(Data(contentsOf: drafts.file(saved)!) == bytes)
        try drafts.remove(saved)
        try require(drafts.entries().isEmpty)
        precondition(!FileManager.default.fileExists(atPath: drafts.file(saved)!.path))
        // A failed manifest commit must preserve the source and remove only its uncommitted copy.
        var blocked = entry; blocked.id = UUID()
        try FileManager.default.createDirectory(at: drafts.root.appendingPathComponent(blocked.id.uuidString + ".json"), withIntermediateDirectories: true)
        do { _ = try drafts.enqueue(blocked, media: original); preconditionFailure("Expected a manifest write failure") } catch { }
        try require(Data(contentsOf: original) == bytes)
        precondition(!FileManager.default.fileExists(atPath: drafts.root.appendingPathComponent(blocked.id.uuidString + ".heic").path))
        print("PASS: offline drafts survive restart, isolate accounts, retain failed sends and original bytes; acknowledge before removal")
        var fingerprint = OriginalResourceFingerprint(limit: 3)
        precondition(fingerprint.append(Data([97])))
        precondition(fingerprint.append(Data([98,99])))
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        precondition(fingerprint.finish()?.matches(length: 3, sha256: abc.uppercased()) == true)
        precondition(fingerprint.finish()?.matches(length: 2, sha256: abc) == false)
        precondition(fingerprint.finish()?.matches(length: 3, sha256: String(repeating: "0", count: 64)) == false)
        precondition(!fingerprint.append(Data([100])))
        precondition(fingerprint.finish() == nil)
        var truncated = OriginalResourceFingerprint(limit: 3)
        precondition(truncated.append(Data([97,98])))
        precondition(truncated.finish()?.matches(length: 3, sha256: abc) == false)
        print("PASS: streaming originals match exact bytes across chunks; reject wrong SHA, truncated and oversized data")
        precondition(PhotoGeography.altitude(nil, belowSeaLevel: false) == nil)
        precondition(PhotoGeography.altitude(0, belowSeaLevel: false) == 0)
        precondition(PhotoGeography.altitude(25.5, belowSeaLevel: true) == -25.5)
        precondition(PhotoGeography.altitude(.nan, belowSeaLevel: false) == nil)
        precondition(PhotoGeography.iso6709("+29.92000+093.98000+3480.5/")?.2 == 3480.5)
        precondition(PhotoGeography.iso6709("-29.92000-093.98000/")?.2 == nil)
        precondition(PhotoGeography.iso6709("+99.00000+093.98000/") == nil)
        precondition(PhotoViewerSwipe.pageOffset(horizontal: -150, vertical: 10, predictedHorizontal: -170) == 1)
        precondition(PhotoViewerSwipe.pageOffset(horizontal: 150, vertical: 10, predictedHorizontal: 170) == -1)
        precondition(PhotoViewerSwipe.pageOffset(horizontal: -40, vertical: 5, predictedHorizontal: -200) == 1)
        precondition(PhotoViewerSwipe.pageOffset(horizontal: 10, vertical: 150, predictedHorizontal: 180) == 0)
        precondition(PhotoViewerSwipe.pageOffset(horizontal: 30, vertical: 2, predictedHorizontal: 40) == 0)
        precondition(PhotoViewerSwipe.pageOffset(horizontal: .nan, vertical: 10, predictedHorizontal: 170) == 0)
        precondition(PhotoViewerSwipe.shouldDismiss(horizontal: 5, vertical: 130, predictedVertical: 150))
        precondition(PhotoViewerSwipe.shouldDismiss(horizontal: 5, vertical: 45, predictedVertical: 270))
        precondition(!PhotoViewerSwipe.shouldDismiss(horizontal: 180, vertical: 60, predictedVertical: 300))
        precondition(!PhotoViewerSwipe.shouldDismiss(horizontal: 0, vertical: -150, predictedVertical: -300))
        precondition(!PhotoViewerSwipe.shouldDismiss(horizontal: 0, vertical: 15, predictedVertical: 300))
        precondition(!PhotoViewerSwipe.shouldDismiss(horizontal: 0, vertical: 50, predictedVertical: 70))
        precondition(!PhotoViewerSwipe.shouldDismiss(horizontal: .nan, vertical: 150, predictedVertical: 200))
        print("PASS: photo viewer down-dismiss threshold, flick, horizontal and upward isolation")
        let raw = Data("""
        [{"id":7,"name":"测试孩子","score":12.5,"cash":0,"items":2,"isPublic":false}, {"id":8,"name":"另一个孩子","score":-2}]
        """.utf8)
        let rows = try Record.list(JSONSerialization.jsonObject(with: raw))
        precondition(rows.count == 2 && rows[0].id == 7 && rows[0].number("score") == 12.5)
        precondition(rows[1].number("score") == -2 && rows[0].flag("isPublic") == false)
        do { _ = try Record.list(["error":"denied"]); fatalError("Error objects must not become empty success lists") } catch is APIError {}
        let rulesPayload: [String: Any] = ["rules": [["id": 1, "name": "按时完成作业"]], "templateRuleIds": [1]]
        let rules = try Record.list(rulesPayload, key: "rules")
        precondition(rules.count == 1 && rules[0].id == 1)
        let empty = try Record.list(["rules": []] as [String: Any], key: "rules")
        precondition(empty.isEmpty)
        do { _ = try Record.list(["error": "denied"], key: "rules"); fatalError("Missing rules must fail") } catch is APIError {}
        do { _ = try Record.list(["rules": "invalid"], key: "rules"); fatalError("Invalid rules must fail") } catch is APIError {}
        precondition(WatchPairingCode.parse("abcd-2345") == "ABCD2345")
        precondition(WatchPairingCode.parse("https://happylife.ai.impx.net/children?watchCode=ABCD2345") == "ABCD2345")
        precondition(WatchPairingCode.parse("https://happylife.ai.xmkurt.com/children?watchCode=ABCD2345") == "ABCD2345")
        for invalid in ["ABCD1234", "123", "https://evil.test/children?watchCode=ABCD2345", "https://happylife.ai.impx.net/children?watchCode=ABCD2345&watchCode=EFGH2345", "https://happylife.ai.impx.net/other?watchCode=ABCD2345", "https://user@happylife.ai.impx.net/children?watchCode=ABCD2345"] {
            precondition(WatchPairingCode.parse(invalid) == nil)
        }
        precondition(ActivityMapLabel.title(nickname: " 山翁 ", placeName: " 巴松措 ") == "山翁 · 巴松措")
        precondition(ActivityMapLabel.title(nickname: "", placeName: "错高乡") == "活动成员 · 错高乡")
        precondition(ActivityMapLabel.title(nickname: "山翁", placeName: " ") == "山翁 · 地点未命名")
        let utc = TimeZone(secondsFromGMT: 0)!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let locale = Locale(identifier: "en_US")
        let timestamp = "2026-11-01T01:00:00Z"
        precondition(ActivityListDate.label(startsAt: timestamp, createdAt: "", timeZone: losAngeles, locale: locale) == "活动日期 Oct 31, 2026")
        precondition(ActivityListDate.label(startsAt: timestamp, createdAt: "", timeZone: tokyo, locale: locale) == "活动日期 Nov 1, 2026")
        for zone in [utc, losAngeles, tokyo] {
            precondition(ActivityListDate.label(startsAt: "2026-11-01", createdAt: "", timeZone: zone, locale: locale) == "活动日期 Nov 1, 2026")
        }
        precondition(ActivityListDate.value(startsAt: "2026-11-01T09:00:00+08:00", createdAt: "", timeZone: utc) == ActivityListDate.parse(timestamp))
        precondition(ActivityListDate.value(startsAt: "invalid", createdAt: timestamp) == ActivityListDate.parse(timestamp))
        precondition(ActivityListDate.label(startsAt: "", createdAt: timestamp, timeZone: utc, locale: locale) == "创建于 Nov 1, 2026")
        precondition(ActivityListDate.value(startsAt: "2026-02-30", createdAt: "") == nil)
        precondition(ActivityListDate.label(startsAt: "", createdAt: "") == "日期未设置")
        print("Native model and activity date checks passed: local dates, date-only values, offsets and fallback")
    }
}
