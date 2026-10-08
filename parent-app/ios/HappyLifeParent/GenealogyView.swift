import SwiftUI

private func genealogyQuery(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? ""
}

// All genealogy reads and writes use FamilyStore's AgentIdentity bearer session.
struct GenealogyView: View {
    @ObservedObject var store: FamilyStore
    @State private var trees: [Record] = []
    @State private var requests: [Record] = []
    @State private var found: [Record] = []
    @State private var query = ""
    @State private var treeName = ""
    @State private var surname = ""
    @State private var treeDescription = ""
    @State private var joining: Record?
    @State private var joinName = ""
    @State private var joinMessage = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section("我的族谱") {
                if trees.isEmpty { Text("还没有加入族谱").foregroundStyle(.secondary) }
                ForEach(trees) { tree in
                    NavigationLink { GenealogyDetailView(store: store, treeID: tree.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tree.text("name")).font(.headline)
                            Text("\(tree.int("peopleCount")) 位人物 · \(tree.text("role") == "owner" ? "管理员" : "成员")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("寻找族谱") {
                TextField("输入族谱名称或姓氏", text: $query).textInputAutocapitalization(.never)
                Button("查找", systemImage: "magnifyingglass") { Task { await search() } }.disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                ForEach(found) { tree in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tree.text("name"))
                            if !tree.text("surname").isEmpty { Text(tree.text("surname") + "氏").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("申请加入") { joining = tree }.disabled(busy)
                    }
                }
                ForEach(requests) { request in
                    LabeledContent(request.text("treeName"), value: status(request.text("status"))).font(.subheadline)
                }
            }
            Section("建立新族谱") {
                TextField("族谱名称", text: $treeName)
                TextField("家族姓氏（可选）", text: $surname)
                TextField("简介（仅成员可见）", text: $treeDescription, axis: .vertical).lineLimit(2...4)
                Button("创建族谱", systemImage: "plus.circle.fill") { Task { await create() } }.disabled(busy || treeName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }
        }
        .frame(maxWidth: 860).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("家族族谱")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $joining) { tree in
            NavigationStack {
                Form {
                    Section { Text("申请加入「\(tree.text("name"))」"); TextField("你的姓名", text: $joinName); TextField("介绍你与家族的关系（可选）", text: $joinMessage, axis: .vertical).lineLimit(2...4) }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("提交申请") { Task { await join(tree) } }.disabled(busy || joinName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                .navigationTitle("加入族谱")
                .toolbar { Button("取消") { joining = nil } }
            }
        }
    }
    private func status(_ value: String) -> String {
        switch value { case "pending": "等待审核"; case "approved": "已通过"; default: "未通过" }
    }
    private func load() async {
        do {
            trees = try Record.list(await store.call("/api/genealogies"))
            requests = try Record.list(await store.call("/api/genealogies/my-join-requests"))
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func search() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2 && value.count <= 50 else { throw APIError.message("请输入 2–50 字的名称或姓氏") }
            found = try Record.list(await store.call("/api/genealogies/discover?q=\(genealogyQuery(value))"))
        } catch { self.error = error.localizedDescription }
    }
    private func create() async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await store.call("/api/genealogies", method: "POST", body: ["name": treeName.trimmingCharacters(in: .whitespacesAndNewlines), "surname": surname.trimmingCharacters(in: .whitespacesAndNewlines), "description": treeDescription.trimmingCharacters(in: .whitespacesAndNewlines)])
            treeName = ""; surname = ""; treeDescription = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
    private func join(_ tree: Record) async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await store.call("/api/genealogies/\(tree.id)/join-requests", method: "POST", body: ["displayName": joinName.trimmingCharacters(in: .whitespacesAndNewlines), "message": joinMessage.trimmingCharacters(in: .whitespacesAndNewlines)])
            joining = nil; joinName = ""; joinMessage = ""; await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct GenealogyDetailView: View {
    @ObservedObject var store: FamilyStore
    let treeID: Int
    @State private var tree: Record?
    @State private var people: [Record] = []
    @State private var relationships: [Record] = []
    @State private var requests: [Record] = []
    @State private var query = ""
    @State private var hasMore = false
    @State private var selected: Record?
    @State private var name = ""
    @State private var generation = ""
    @State private var branch = ""
    @State private var note = ""
    @State private var editingID = 0
    @State private var fromID = 0
    @State private var toID = 0
    @State private var kind = "parent"
    @State private var matches: [Int: Int] = [:]
    @State private var busy = false
    @State private var error: String?
    private var owner: Bool { tree?.text("role") == "owner" }
    private var base: String { "/api/genealogies/\(treeID)" }

    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let tree {
                Section {
                    Text(tree.text("name")).font(.title2.bold())
                    Text("\(tree.int("peopleCount")) 位人物 · \(tree.int("memberCount")) 位已加入成员").foregroundStyle(.secondary)
                    if !tree.text("description").isEmpty { Text(tree.text("description")) }
                }
            }
            if owner && !requests.isEmpty {
                Section("待审核申请") {
                    ForEach(requests) { request in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(request.text("displayName")).font(.headline)
                            Text("用户中心账号：" + request.text("accountName")).font(.caption).foregroundStyle(.secondary)
                            if !request.text("message").isEmpty { Text(request.text("message")) }
                            Picker("关联人物", selection: Binding(get: { matches[request.id] ?? 0 }, set: { matches[request.id] = $0 })) {
                                Text("新建本人记录").tag(0)
                                ForEach(people.filter { !$0.flag("isLinked") }) { person in Text(person.text("displayName") + " #\(person.id)").tag(person.id) }
                            }
                            HStack {
                                Button("通过") { Task { await decide(request, "approve") } }
                                Spacer()
                                Button("拒绝", role: .destructive) { Task { await decide(request, "reject") } }
                            }.disabled(busy)
                        }
                    }
                }
            }
            Section("查找家族成员") {
                HStack {
                    TextField("姓名或支系", text: $query)
                    Button("查找") { Task { await loadPeople() } }.disabled(busy)
                }
                ForEach(people) { person in
                    Button { selected = person } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.text("displayName")).font(.headline)
                                Text([person.text("generationLabel"), person.text("branchName")].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if person.flag("isSelf") { Text("我").font(.caption).foregroundStyle(.teal) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }.foregroundStyle(.primary)
                }
                if hasMore { Text("结果超过 100 位，请输入姓名或支系缩小范围。 ").font(.caption).foregroundStyle(.secondary) }
            }
            if let selected {
                Section(selected.text("displayName") + " · 亲属关系") {
                    if !selected.text("note").isEmpty { Text(selected.text("note")) }
                    ForEach(relationships.filter { $0.int("fromPersonId") == selected.id || $0.int("toPersonId") == selected.id }) { relation in
                        let selectedIsFrom = relation.int("fromPersonId") == selected.id
                        let otherID = selectedIsFrom ? relation.int("toPersonId") : relation.int("fromPersonId")
                        HStack {
                            VStack(alignment: .leading) {
                                Text(relation.text("kind") == "spouse" ? "配偶" : selectedIsFrom ? "子女" : "父母").font(.caption).foregroundStyle(.secondary)
                                Button(selectedIsFrom ? relation.text("toName") : relation.text("fromName")) { Task { await selectPerson(otherID) } }
                            }
                            Spacer()
                            if owner { Button("移除", role: .destructive) { Task { await remove(relation) } }.disabled(busy) }
                        }
                    }
                    if owner { Button("编辑人物") { startEditing(selected) } }
                }
            }
            if owner {
                Section(editingID == 0 ? "补录成员" : "编辑成员") {
                    TextField("姓名", text: $name)
                    TextField("辈分（可选）", text: $generation)
                    TextField("支系（可选）", text: $branch)
                    TextField("备注（仅成员可见）", text: $note, axis: .vertical).lineLimit(2...4)
                    HStack {
                        Button("保存成员") { Task { await savePerson() } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                        if editingID != 0 { Button("取消编辑") { clearEditor() } }
                    }
                }
                Section("建立亲属关系") {
                    Picker("父母或配偶一方", selection: $fromID) { Text("请选择").tag(0); ForEach(people) { Text($0.text("displayName") + " #\($0.id)").tag($0.id) } }
                    Picker("关系", selection: $kind) { Text("父母 → 子女").tag("parent"); Text("配偶").tag("spouse") }
                    Picker("子女或配偶另一方", selection: $toID) { Text("请选择").tag(0); ForEach(people) { Text($0.text("displayName") + " #\($0.id)").tag($0.id) } }
                    Button("添加关系") { Task { await addRelation() } }.disabled(busy || fromID == 0 || toID == 0 || fromID == toID)
                }
            }
        }
        .frame(maxWidth: 860).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(tree?.text("name") ?? "族谱")
        .refreshable { await load() }
        .task { await load() }
    }
    private func load() async {
        do {
            tree = Record(fields: try object(await store.call(base)))
            await loadPeople()
            relationships = try Record.list(await store.call(base + "/relationships"))
            requests = owner ? try Record.list(await store.call(base + "/join-requests")) : []
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func loadPeople() async {
        do {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count <= 80 else { throw APIError.message("搜索内容不能超过 80 字") }
            let result = try object(await store.call(base + "/people?q=\(genealogyQuery(q))"))
            people = try Record.list(result, key: "people")
            hasMore = result["hasMore"] as? Bool ?? false
            if let selected, let latest = people.first(where: { $0.id == selected.id }) { self.selected = latest }
        } catch { self.error = error.localizedDescription }
    }
    private func object(_ value: Any) throws -> [String: Any] {
        guard let result = value as? [String: Any] else { throw APIError.message("服务返回的数据格式不正确。") }
        return result
    }
    private func mutate(_ path: String, method: String = "POST", body: [String: Any]? = nil) async {
        busy = true; error = nil; defer { busy = false }
        do { _ = try await store.call(path, method: method, body: body); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func decide(_ request: Record, _ decision: String) async {
        var body: [String: Any] = ["decision": decision]
        if decision == "approve", let match = matches[request.id], match > 0 { body["personId"] = match }
        await mutate(base + "/join-requests/\(request.id)/decision", body: body)
    }
    private func startEditing(_ person: Record) {
        editingID = person.id; name = person.text("displayName"); generation = person.text("generationLabel"); branch = person.text("branchName"); note = person.text("note")
    }
    private func clearEditor() { editingID = 0; name = ""; generation = ""; branch = ""; note = "" }
    private func savePerson() async {
        let path = editingID == 0 ? base + "/people" : base + "/people/\(editingID)"
        let body = ["displayName": name.trimmingCharacters(in: .whitespacesAndNewlines), "generationLabel": generation.trimmingCharacters(in: .whitespacesAndNewlines), "branchName": branch.trimmingCharacters(in: .whitespacesAndNewlines), "note": note.trimmingCharacters(in: .whitespacesAndNewlines)]
        await mutate(path, method: editingID == 0 ? "POST" : "PUT", body: body)
        if error == nil { clearEditor() }
    }
    private func addRelation() async {
        await mutate(base + "/relationships", body: ["fromPersonId": fromID, "toPersonId": toID, "kind": kind])
        if error == nil { fromID = 0; toID = 0 }
    }
    private func remove(_ relation: Record) async { await mutate(base + "/relationships/\(relation.id)", method: "DELETE") }
    private func selectPerson(_ id: Int) async {
        do { selected = Record(fields: try object(await store.call(base + "/people/\(id)"))) }
        catch { self.error = error.localizedDescription }
    }
}
