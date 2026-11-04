import AgentIdentity
import SwiftUI

struct CreditView: View {
    @ObservedObject var store: FamilyStore
    let child: Record
    @State private var detail: Record?
    @State private var title = ""
    @State private var dueAt = Date().addingTimeInterval(86400)
    @State private var reason = "honesty"
    @State private var delta = 1
    @State private var note = ""
    @State private var busy = false
    @State private var message: String?

    private var path: String { "/api/children/\(child.id)/credit" }
    private var enabled: Bool { detail?.flag("enabled") ?? false }
    private var commitments: [Record] { rows("commitments") }
    private var events: [Record] { rows("events") }
    private var disputes: [Record] { rows("disputes") }

    private func rows(_ key: String) -> [Record] {
        (detail?.fields[key] as? [[String: Any]] ?? []).map { Record(fields: $0) }
    }

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "信用分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Text(enabled ? "\(detail?.int("score") ?? 80) / 100" : String(localized: "未开通", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        .font(.title2.bold()).foregroundStyle(.teal)
                }
                Text(String(localized: "记录守约与责任行为，与可兑换积分分别计算。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.footnote).foregroundStyle(.secondary)
                if !enabled {
                    Button(String(localized: "从 80 分开通", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { act("\(path)/enable") }
                }
            }
            if enabled {
                Section(String(localized: "新建约定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    TextField(String(localized: "约定内容", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $title).textInputAutocapitalization(.never)
                    DatePicker(String(localized: "截止时间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $dueAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Button(String(localized: "保存约定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        act("\(path)/commitments", body: [
                            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                            "dueAt": ISO8601DateFormatter().string(from: dueAt),
                            "requestId": UUID().uuidString
                        ]) { title = "" }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                Section(String(localized: "约定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    if commitments.isEmpty { Text(String(localized: "还没有约定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                    ForEach(commitments) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.text("title")).font(.headline)
                            Text(String(localized: "截止 \(localDateText(item.text("dueAt"))) · \(status(item.text("status")))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                .font(.caption).foregroundStyle(.secondary)
                            if ["open", "pending", "late_pending"].contains(item.text("status")) {
                                HStack {
                                    Button(String(localized: "确认完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { resolve(item, "completed") }.buttonStyle(.bordered)
                                    if (ISO8601DateFormatter().date(from: item.text("dueAt")) ?? .distantFuture) <= Date() {
                                        Button(String(localized: "确认逾期", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { resolve(item, "overdue") }.buttonStyle(.bordered)
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section(String(localized: "家长调整", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Picker(String(localized: "原因", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $reason) {
                        Text(String(localized: "诚实说明", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("honesty")
                        Text(String(localized: "承担责任", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("responsibility")
                        Text(String(localized: "虚报完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("false_report")
                        Text(String(localized: "其他调整", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("adjustment")
                    }
                    Stepper(String(localized: "变化 \(delta > 0 ? "+" : "")\(delta) 分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: $delta, in: -5...5)
                    TextField(String(localized: "说明", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $note)
                    Text(String(localized: "预计 \(detail?.int("score") ?? 0) → \((detail?.int("score") ?? 0) + delta) 分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(String(localized: "确认调整", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        act("\(path)/adjustments", body: ["reasonCode": reason, "delta": delta,
                             "note": note, "requestId": UUID().uuidString]) { note = "" }
                    }.disabled(delta == 0 || ((detail?.int("score") ?? 0) + delta) < 0 || ((detail?.int("score") ?? 0) + delta) > 100 ||
                               (reason == "false_report" && delta != -5) ||
                               (["honesty", "responsibility"].contains(reason) && !(1...3).contains(delta)))
                }
                Section(String(localized: "变动记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    if events.isEmpty { Text(String(localized: "还没有记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(event.text("note").isEmpty ? event.text("reasonCode") : event.text("note")); Spacer(); Text("\(event.int("delta") > 0 ? "+" : "")\(event.int("delta"))") }
                            Text(localDateText(event.text("createdAt"))).font(.caption).foregroundStyle(.secondary)
                            if event.text("reasonCode") != "opened" && event.text("reasonCode") != "reversal" &&
                                !events.contains(where: { $0.int("reversalOfEventId") == event.id }) {
                                Button(String(localized: "撤销这笔记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                                    let explanation = note.trimmingCharacters(in: .whitespacesAndNewlines)
                                    act("\(path)/events/\(event.id)/reverse", body: ["note": explanation])
                                }.disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                            }
                        }
                    }
                }
                if !disputes.isEmpty {
                    Section(String(localized: "孩子的异议", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        ForEach(disputes) { dispute in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(dispute.text("reason"))
                                Text(dispute.text("status") == "pending" ? String(localized: "待处理", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : dispute.text("parentResponse"))
                                    .font(.caption).foregroundStyle(.secondary)
                                if dispute.text("status") == "pending" {
                                    HStack {
                                        Button(String(localized: "采纳并撤销扣分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { resolveDispute(dispute, "accepted") }
                                        Button(String(localized: "保留扣分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { resolveDispute(dispute, "rejected") }
                                    }.buttonStyle(.bordered).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                                }
                            }
                        }
                    }
                }
            }
            if let message { Section { Text(message).foregroundStyle(.red) } }
        }
        .navigationTitle(String(localized: "\(child.text("name"))的信用分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .refreshable { await reload() }
        .task { await reload() }
        .disabled(busy)
    }

    private func status(_ code: String) -> String {
        ["open": String(localized: "进行中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "pending": String(localized: "待家长确认", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "overdue": String(localized: "已逾期", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "late_pending": String(localized: "补救待确认", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "completed": String(localized: "已完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))][code] ?? code
    }

    private func reload() async {
        do {
            guard let value = try await store.call(path) as? [String: Any] else { throw APIError.message(String(localized: "信用分数据格式不正确", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            detail = Record(fields: value)
            message = nil
        } catch { message = momentDisplayError(error) }
    }

    private func act(_ endpoint: String, body: [String: Any]? = nil, after: (() -> Void)? = nil) {
        Task {
            busy = true
            defer { busy = false }
            do {
                _ = try await store.call(endpoint, method: "POST", body: body)
                after?()
                await reload()
                try await store.refreshBalancesAndLedger()
            } catch { message = momentDisplayError(error) }
        }
    }

    private func resolve(_ item: Record, _ action: String) {
        act("\(path)/commitments/\(item.id)/resolve", body: ["action": action])
    }

    private func resolveDispute(_ item: Record, _ action: String) {
        act("\(path)/disputes/\(item.id)/resolve", body: ["action": action, "response": note]) { note = "" }
    }
}
