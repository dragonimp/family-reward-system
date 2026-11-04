import Foundation
import AgentIdentityLocalization

@main struct LocalTimeChecks {
    static func main() {
        precondition(TimeZone.current.identifier == "America/Los_Angeles")
        for language in ["en", "fr-FR", "zh-Hans"] {
            let suite = "time-language-test-" + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            AgentIdentityLanguage.publishEffectiveLanguage(language, defaults: defaults)
            UserDefaults.standard.setVolatileDomain(defaults.persistentDomain(forName: suite) ?? [:], forName: UserDefaults.argumentDomain)
            defaults.removePersistentDomain(forName: suite)
            let display = localDateText("2026-10-30T00:00:00Z")
            precondition(display.contains("29"), "UTC October 30 must display as local October 29: \(display)")
            precondition(display.contains("5:00") || display.contains("17:00"), "Expected local 17:00: \(display)")
            precondition(display.contains(language == "zh-Hans" ? "当地时间" : "local time"))
            let watchDisplay = watchLocalTime("2026-10-30T00:00:00Z")
            precondition(watchDisplay.contains("29") && (watchDisplay.contains("5:00") || watchDisplay.contains("17:00")))
            print("\(language): \(display)")
        }
        precondition(localDateText("2026-10-30") == "2026-10-30", "Calendar dates must remain unchanged")
        print("Local timezone, unsupported-language fallback, and calendar-date checks passed")
    }
}
