import Foundation
@main struct NativeModelTests {
    static func main() throws {
        precondition(PhotoGeography.altitude(nil, belowSeaLevel: false) == nil)
        precondition(PhotoGeography.altitude(0, belowSeaLevel: false) == 0)
        precondition(PhotoGeography.altitude(25.5, belowSeaLevel: true) == -25.5)
        precondition(PhotoGeography.altitude(.nan, belowSeaLevel: false) == nil)
        precondition(PhotoGeography.iso6709("+29.92000+093.98000+3480.5/")?.2 == 3480.5)
        precondition(PhotoGeography.iso6709("-29.92000-093.98000/")?.2 == nil)
        precondition(PhotoGeography.iso6709("+99.00000+093.98000/") == nil)
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
