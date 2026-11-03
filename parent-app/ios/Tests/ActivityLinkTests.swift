import Foundation
@main struct ActivityLinkTests {
    static func main() {
        let tenant = UUID(), activity = UUID()
        for scheme in ["linkofamily", "linkomoment", "linkomomentx"] {
            var parts = URLComponents(); parts.scheme = scheme; parts.host = "activity"
            parts.queryItems = [.init(name: "tenantId", value: tenant.uuidString.lowercased()), .init(name: "activityId", value: activity.uuidString), .init(name: "invite", value: "a&b<c+/")]
            let parsed = MomentActivityLink(url: parts.url!)
            precondition(parsed?.tenantID == tenant && parsed?.activityID == activity && parsed?.invitation == "a&b<c+/")
        }
        for raw in ["linkofamily://login-complete/", "https://evil.example/activity", "linkomoment://activity?tenantId=bad&activityId=bad", "linkomoment://user@activity?tenantId=\(tenant)&activityId=\(activity)", "linkomoment://activity?tenantId=\(tenant)&tenantId=\(tenant)&activityId=\(activity)", "linkomoment://activity?tenantId=\(tenant)&activityId=\(activity)&invite=", "linkomoment://activity?tenantId=\(tenant)&activityId=\(activity)&redirect=https://evil.example"] {
            precondition(MomentActivityLink(url: URL(string: raw)!) == nil)
        }
        print("PASS: new/legacy/shared activity schemes, UUID case and invitation round-trip; login callback and malformed/ambiguous links rejected")
    }
}
