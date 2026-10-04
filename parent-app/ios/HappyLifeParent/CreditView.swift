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
                LabeledContent("信用分") {
                    Text(enabled ? "\(detail?.int("score") ?? 80) / 100" : "未开通")
                        .font(.title2.bold()).foregroundStyle(.teal)
                }
                Text("记录守约与责任行为，与可兑换积分分别计算。").font(.footnote).foregroundStyle(.secondary)
                if !enabled {
                    Button("从 80 分开通") { act("\(path)/enable") }
                }
            }
            if enabled {
                Section("新建约定") {
                    TextField("约定内容", text: $title).textInputAutocapitalization(.never)
                    DatePicker("截止时间", selection: $dueAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Button("保存约定") {
                        act("\(path)/commitments", body: [
                            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                            "dueAt": ISO8601DateFormatter().string(from: dueAt),
                            "requestId": UUID().uuidString
                        ]) { title = "" }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                Section("约定") {
                    if commitments.isEmpty { Text("还没有约定").foregroundStyle(.secondary) }
                    ForEach(commitments) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.text("title")).font(.headline)
                            Text("截止 \(beijingDate(item.text("dueAt"))) · \(status(item.text("status")))")
                                .font(.caption).foregroundStyle(.secondary)
                            if ["open", "pending", "late_pending"].contains(item.text("status")) {
                                HStack {
                                    Button("确认完成") { resolve(item, "completed") }.buttonStyle(.bordered)
                                    if (ISO8601DateFormatter().date(from: item.text("dueAt")) ?? .distantFuture) <= Date() {
                                        Button("确认逾期") { resolve(item, "overdue") }.buttonStyle(.bordered)
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("家长调整") {
                    Picker("原因", selection: $reason) {
                        Text("诚实说明").tag("honesty")
                        Text("承担责任").tag("responsibility")
                        Text("虚报完成").tag("false_report")
                        Text("其他调整").tag("adjustment")
                    }
                    Stepper("变化 \(delta > 0 ? "+" : "")\(delta) 分", value: $delta, in: -5...5)
                    TextField("说明", text: $note)
                    Text("预计 \(detail?.int("score") ?? 0) → \((detail?.int("score") ?? 0) + delta) 分")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("确认调整") {
                        act("\(path)/adjustments", body: ["reasonCode": reason, "delta": delta,
                             "note": note, "requestId": UUID().uuidString]) { note = "" }
                    }.disabled(delta == 0 || ((detail?.int("score") ?? 0) + delta) < 0 || ((detail?.int("score") ?? 0) + delta) > 100 ||
                               (reason == "false_report" && delta != -5) ||
                               (["honesty", "responsibility"].contains(reason) && !(1...3).contains(delta)))
                }
                Section("变动记录") {
                    if events.isEmpty { Text("还没有记录").foregroundStyle(.secondary) }
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(event.text("note").isEmpty ? event.text("reasonCode") : event.text("note")); Spacer(); Text("\(event.int("delta") > 0 ? "+" : "")\(event.int("delta"))") }
                            Text(beijingDate(event.text("createdAt"))).font(.caption).foregroundStyle(.secondary)
                            if event.text("reasonCode") != "opened" && event.text("reasonCode") != "reversal" &&
                                !events.contains(where: { $0.int("reversalOfEventId") == event.id }) {
                                Button("撤销这笔记录") {
                                    let explanation = note.trimmingCharacters(in: .whitespacesAndNewlines)
                                    act("\(path)/events/\(event.id)/reverse", body: ["note": explanation])
                                }.disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                            }
                        }
                    }
                }
                if !disputes.isEmpty {
                    Section("孩子的异议") {
                        ForEach(disputes) { dispute in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(dispute.text("reason"))
                                Text(dispute.text("status") == "pending" ? "待处理" : dispute.text("parentResponse"))
                                    .font(.caption).foregroundStyle(.secondary)
                                if dispute.text("status") == "pending" {
                                    HStack {
                                        Button("采纳并撤销扣分") { resolveDispute(dispute, "accepted") }
                                        Button("保留扣分") { resolveDispute(dispute, "rejected") }
                                    }.buttonStyle(.bordered).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                                }
                            }
                        }
                    }
                }
            }
            if let message { Section { Text(message).foregroundStyle(.red) } }
        }
        .navigationTitle("\(child.text("name"))的信用分")
        .refreshable { await reload() }
        .task { await reload() }
        .disabled(busy)
    }

    private func status(_ code: String) -> String {
        ["open": "进行中", "pending": "待家长确认", "overdue": "已逾期", "late_pending": "补救待确认", "completed": "已完成"][code] ?? code
    }

    private func reload() async {
        do {
            guard let value = try await store.call(path) as? [String: Any] else { throw APIError.message("信用分数据格式不正确") }
            detail = Record(fields: value)
            message = nil
        } catch { message = error.localizedDescription }
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
            } catch { message = error.localizedDescription }
        }
    }

    private func resolve(_ item: Record, _ action: String) {
        act("\(path)/commitments/\(item.id)/resolve", body: ["action": action])
    }

    private func resolveDispute(_ item: Record, _ action: String) {
        act("\(path)/disputes/\(item.id)/resolve", body: ["action": action, "response": note]) { note = "" }
    }
}
