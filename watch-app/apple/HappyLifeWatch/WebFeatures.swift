import SwiftUI

enum WatchTheme {
    static func colors(_ face: String) -> Color {
        switch face {
        case "hellokitty", "flowers": return Color(red: 0.35, green: 0.08, blue: 0.22)
        case "starlight", "snow": return Color(red: 0.08, green: 0.22, blue: 0.38)
        case "space", "night", "meteor": return Color(red: 0.15, green: 0.10, blue: 0.32)
        case "rainbow", "pixel": return Color(red: 0.32, green: 0.20, blue: 0.08)
        default: return Color(red: 0.06, green: 0.23, blue: 0.13)
        }
    }
}

struct FriendsView: View {
    @EnvironmentObject private var store: WatchStore
    var leaderboard = false
    @State private var code = ""
    var body: some View {
        List {
            if !leaderboard {
                Button("生成好友码") { Task { await store.makeFriendCode() } }
                if let friendCode = store.friendCode {
                    Text(friendCode.code).font(.title2.monospacedDigit()).privacySensitive()
                    Text("有效期至 \(beijingTime(friendCode.expiresAt))（北京时间）")
                        .font(.footnote)
                }
                TextField("好友的认证码", text: $code)
                Button("添加好友") {
                    Task { await store.addFriend(code: code); code = "" }
                }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let rows = leaderboard ? (store.friends?.leaderboard ?? []) : (store.friends?.friends ?? [])
            if rows.isEmpty { Text(leaderboard ? "暂无排行" : "暂无好友") }
            ForEach(rows) { friend in
                VStack(alignment: .leading) {
                    Text("\(friend.rank.map { "\($0). " } ?? "")\(friend.name)\(friend.isSelf == true ? " · 我" : "")")
                    Text("\(friend.score.formatted()) 分").foregroundStyle(.green)
                }
            }
            Button("刷新") { Task { await store.loadSection("friends") } }
        }.disabled(store.busy).navigationTitle(leaderboard ? "好友积分榜" : "我的好友")
            .task { await store.loadSection("friends") }
    }

    private func beijingTime(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return "请重新生成好友码" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

struct WarmMomentView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var parentID = 0
    @State private var content = ""
    var body: some View {
        List {
            Text("爸爸妈妈的闪光时刻").font(.headline)
            if store.parents.isEmpty {
                Text("请家长先配置家庭成员")
                Button("重新加载") { Task { await store.loadSection("parents") } }
            } else {
                Picker("想记录谁", selection: $parentID) {
                    Text("请选择").tag(0)
                    ForEach(store.parents) { Text($0.roleLabel).tag($0.id) }
                }
                TextField("发生了什么", text: $content)
                Text("可使用手表系统听写输入，最多 500 字。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("保存暖心时刻") {
                    Task {
                        if await store.saveWarmMoment(parentID: parentID, content: content) { content = "" }
                    }
                }.disabled(parentID == 0 || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 500)
            }
        }.disabled(store.busy).navigationTitle("暖心时刻")
            .task { await store.loadSection("parents") }
    }
}

struct GrowthView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if let report = store.growth {
                Text(report.praise).font(.headline)
                Text(report.nextStep)
                Text("继续加油，每一点进步都值得被看见。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else { Text(store.busy ? "正在准备今天的鼓励…" : "今天也要开心成长。") }
            Button("刷新") { Task { await store.loadSection("growth") } }
        }.disabled(store.busy).navigationTitle("今日鼓励")
            .task { await store.loadSection("growth") }
    }
}

struct FaceSettingsView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            Text("设置Linko Family App 内的主题外观。")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(store.settings?.availableFaces ?? []) { face in
                Button {
                    Task { await store.setFace(face) }
                } label: {
                    HStack {
                        Circle().fill(WatchTheme.colors(face.code)).frame(width: 16, height: 16)
                        Text(face.name + (face.vip ? " · VIP" : ""))
                        if face.code == store.face { Image(systemName: "checkmark") }
                        if !face.available { Image(systemName: "lock") }
                    }
                }.disabled(!face.available)
            }
            Button("刷新") { Task { await store.loadSection("settings") } }
        }.disabled(store.busy).navigationTitle("表盘设置")
            .task { await store.loadSection("settings") }
    }
}
