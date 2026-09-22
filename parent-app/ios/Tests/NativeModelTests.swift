import Foundation
@main struct NativeModelTests {
    static func main() throws {
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
        for invalid in ["ABCD1234", "123", "https://evil.test/children?watchCode=ABCD2345", "https://happylife.ai.impx.net/children?watchCode=ABCD2345&watchCode=EFGH2345", "https://happylife.ai.impx.net/other?watchCode=ABCD2345", "https://user@happylife.ai.impx.net/children?watchCode=ABCD2345"] {
            precondition(WatchPairingCode.parse(invalid) == nil)
        }
        print("Native API model checks passed")
    }
}
