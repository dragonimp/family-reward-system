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
    @State private var editName = ""
    @State private var editGeneration = ""
    @State private var editBranch = ""
    @State private var editNote = ""
    @State private var editBusy = false
    @State private var editError: String?
    @State private var showAddPerson = false
    @State private var relatedPersonID = 0
    @State private var relationKind = "parent"
    @State private var invitationURL: URL?
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
            Section("家族成员") {
                HStack {
                    TextField("按姓名或支系查找", text: $query)
                    Button("查找") { Task { await loadPeople() } }.disabled(busy)
                }
                ForEach(people) { person in
                    Button { openPerson(person) } label: {
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
            if owner {
                Section {
                    DisclosureGroup("新增家族成员", isExpanded: $showAddPerson) {
                        Text("此处只用于新增；修改已有成员请点选上方姓名。")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("新成员姓名", text: $name)
                        TextField("辈分（可选）", text: $generation)
                        TextField("支系（可选）", text: $branch)
                        TextField("备注（仅成员可见）", text: $note, axis: .vertical).lineLimit(2...4)
                        Button("添加新成员") { Task { await savePerson() } }
                            .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    }
                }
            }
        }
        .frame(maxWidth: 860).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(tree?.text("name") ?? "族谱")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $selected) { person in
            NavigationStack {
                Form {
                    if let editError { Section { Text(editError).foregroundStyle(.red) } }
                    Section("成员资料") {
                        if owner {
                            TextField("姓名", text: $editName)
                            TextField("辈分（可选）", text: $editGeneration)
                            TextField("支系（可选）", text: $editBranch)
                            TextField("备注（仅成员可见）", text: $editNote, axis: .vertical).lineLimit(2...4)
                            Button("保存资料") { Task { await saveEdit(person.id) } }
                                .disabled(editBusy || editName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                        } else {
                            LabeledContent("姓名", value: person.text("displayName"))
                            if !person.text("generationLabel").isEmpty { LabeledContent("辈分", value: person.text("generationLabel")) }
                            if !person.text("branchName").isEmpty { LabeledContent("支系", value: person.text("branchName")) }
                            if !person.text("note").isEmpty { Text(person.text("note")) }
                        }
                    }
                    Section("亲属关系") {
                        let related = relationships.filter { $0.int("fromPersonId") == person.id || $0.int("toPersonId") == person.id }
                        if related.isEmpty { Text("暂无亲属关系").foregroundStyle(.secondary) }
                        ForEach(related) { relation in
                            let selectedIsFrom = relation.int("fromPersonId") == person.id
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
                    }
                    if owner {
                        Section("为此人添加关系") {
                            Picker("关系", selection: $relationKind) {
                                Text("父母").tag("parent")
                                Text("子女").tag("child")
                                Text("配偶").tag("spouse")
                            }
                            Picker("另一位成员", selection: $relatedPersonID) {
                                Text("请选择").tag(0)
                                ForEach(people.filter { $0.id != person.id }) { other in
                                    Text(other.text("displayName") + " #\(other.id)").tag(other.id)
                                }
                            }
                            Button("添加关系") { Task { await addRelation(person.id) } }
                                .disabled(busy || relatedPersonID == 0)
                        }
                        Section("邀请本人加入") {
                            if person.flag("isLinked") {
                                Text("此人物已绑定用户。").foregroundStyle(.secondary)
                            } else {
                                Text("链接有效 7 天，仅可使用一次；重新生成会让旧链接失效。")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("生成邀请链接") { Task { await createInvitation(person.id) } }.disabled(busy)
                                if let invitationURL { ShareLink("分享邀请链接", item: invitationURL) }
                            }
                        }
                    }
                }
                .navigationTitle(person.text("displayName"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { selected = nil }.disabled(editBusy) }
            }
        }
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
    private func openPerson(_ person: Record) {
        editName = person.text("displayName")
        editGeneration = person.text("generationLabel")
        editBranch = person.text("branchName")
        editNote = person.text("note")
        editError = nil
        relatedPersonID = 0
        invitationURL = nil
        selected = person
    }
    private func savePerson() async {
        let body = ["displayName": name.trimmingCharacters(in: .whitespacesAndNewlines), "generationLabel": generation.trimmingCharacters(in: .whitespacesAndNewlines), "branchName": branch.trimmingCharacters(in: .whitespacesAndNewlines), "note": note.trimmingCharacters(in: .whitespacesAndNewlines)]
        await mutate(base + "/people", body: body)
        if error == nil { name = ""; generation = ""; branch = ""; note = ""; showAddPerson = false }
    }
    private func saveEdit(_ personID: Int) async {
        editBusy = true; editError = nil; defer { editBusy = false }
        let body = ["displayName": editName.trimmingCharacters(in: .whitespacesAndNewlines), "generationLabel": editGeneration.trimmingCharacters(in: .whitespacesAndNewlines), "branchName": editBranch.trimmingCharacters(in: .whitespacesAndNewlines), "note": editNote.trimmingCharacters(in: .whitespacesAndNewlines)]
        do {
            _ = try await store.call(base + "/people/\(personID)", method: "PUT", body: body)
            await load()
            await selectPerson(personID)
        } catch { editError = error.localizedDescription }
    }
    private func addRelation(_ personID: Int) async {
        guard relatedPersonID > 0 else { return }
        let from = relationKind == "parent" ? relatedPersonID : personID
        let to = relationKind == "parent" ? personID : relatedPersonID
        await mutate(base + "/relationships", body: ["fromPersonId": from, "toPersonId": to, "kind": relationKind == "spouse" ? "spouse" : "parent"])
        if error == nil { relatedPersonID = 0 }
    }
    private func createInvitation(_ personID: Int) async {
        busy = true; editError = nil; defer { busy = false }
        do {
            let result = try object(await store.call(base + "/people/\(personID)/invitations", method: "POST"))
            guard let path = result["path"] as? String,
                  let url = URL(string: path, relativeTo: URL(string: "https://happylife.ai.impx.net")!)?.absoluteURL else {
                throw APIError.message("邀请链接格式不正确")
            }
            invitationURL = url
        } catch { editError = error.localizedDescription }
    }
    private func remove(_ relation: Record) async { await mutate(base + "/relationships/\(relation.id)", method: "DELETE") }
    private func selectPerson(_ id: Int) async {
        do { openPerson(Record(fields: try object(await store.call(base + "/people/\(id)")))) }
        catch { self.error = error.localizedDescription }
    }
}
