import AgentIdentity
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
            Section(String(localized: "我的族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                if trees.isEmpty { Text(String(localized: "还没有加入族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                ForEach(trees) { tree in
                    NavigationLink { GenealogyDetailView(store: store, treeID: tree.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tree.text("name")).font(.headline)
                            Text(String(localized: "\(tree.int("peopleCount")) 位人物 · \(tree.text("role") == "owner" ? String(localized: "管理员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(String(localized: "寻找族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                TextField(String(localized: "输入族谱名称或姓氏", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $query).textInputAutocapitalization(.never)
                Button(String(localized: "查找", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "magnifyingglass") { Task { await search() } }.disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                ForEach(found) { tree in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tree.text("name"))
                            if !tree.text("surname").isEmpty { Text(tree.text("surname") + String(localized: "氏", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button(String(localized: "申请加入", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { joining = tree }.disabled(busy)
                    }
                }
                ForEach(requests) { request in
                    LabeledContent(request.text("treeName"), value: status(request.text("status"))).font(.subheadline)
                }
            }
            Section(String(localized: "建立新族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                TextField(String(localized: "族谱名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $treeName)
                TextField(String(localized: "家族姓氏（可选）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $surname)
                TextField(String(localized: "简介（仅成员可见）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $treeDescription, axis: .vertical).lineLimit(2...4)
                Button(String(localized: "创建族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "plus.circle.fill") { Task { await create() } }.disabled(busy || treeName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }
        }
        .frame(maxWidth: 860).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(String(localized: "家族族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $joining) { tree in
            NavigationStack {
                Form {
                    Section { Text(String(localized: "申请加入「\(tree.text("name"))」", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))); TextField(String(localized: "你的姓名", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $joinName); TextField(String(localized: "介绍你与家族的关系（可选）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $joinMessage, axis: .vertical).lineLimit(2...4) }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(String(localized: "提交申请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await join(tree) } }.disabled(busy || joinName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                .navigationTitle(String(localized: "加入族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                .toolbar { Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { joining = nil } }
            }
        }
    }
    private func status(_ value: String) -> String {
        switch value { case "pending": String(localized: "等待审核", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); case "approved": String(localized: "已通过", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); default: String(localized: "未通过", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    private func load() async {
        do {
            trees = try Record.list(await store.call("/api/genealogies"))
            requests = try Record.list(await store.call("/api/genealogies/my-join-requests"))
            error = nil
        } catch is CancellationError {} catch { self.error = momentDisplayError(error) }
    }
    private func search() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2 && value.count <= 50 else { throw APIError.message(String(localized: "请输入 2–50 字的名称或姓氏", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            found = try Record.list(await store.call("/api/genealogies/discover?q=\(genealogyQuery(value))"))
        } catch { self.error = momentDisplayError(error) }
    }
    private func create() async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await store.call("/api/genealogies", method: "POST", body: ["name": treeName.trimmingCharacters(in: .whitespacesAndNewlines), "surname": surname.trimmingCharacters(in: .whitespacesAndNewlines), "description": treeDescription.trimmingCharacters(in: .whitespacesAndNewlines)])
            treeName = ""; surname = ""; treeDescription = ""
            await load()
        } catch { self.error = momentDisplayError(error) }
    }
    private func join(_ tree: Record) async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await store.call("/api/genealogies/\(tree.id)/join-requests", method: "POST", body: ["displayName": joinName.trimmingCharacters(in: .whitespacesAndNewlines), "message": joinMessage.trimmingCharacters(in: .whitespacesAndNewlines)])
            joining = nil; joinName = ""; joinMessage = ""; await load()
        } catch { self.error = momentDisplayError(error) }
    }
}

struct GenealogyDetailView: View {
    @ObservedObject var store: FamilyStore
    let treeID: Int
    @State private var tree: Record?
    @State private var people: [Record] = []
    @State private var relationships: [Record] = []
    @State private var householdLinks: [Record] = []
    @State private var inferred: [Record] = []
    @State private var inferenceLoading = false
    @State private var inferenceError: String?
    @State private var requests: [Record] = []
    @State private var query = ""
    @State private var hasMore = false
    @State private var selected: Record?
    @State private var editName = ""
    @State private var editGeneration = ""
    @State private var editBranch = ""
    @State private var editNote = ""
    @State private var editGender = ""
    @State private var editBirthYear = ""
    @State private var editBirthMonth = ""
    @State private var editBirthDay = ""
    @State private var editBirthPrecision = "none"
    @State private var editBusy = false
    @State private var editError: String?
    @State private var showAddPerson = false
    @State private var birthdayCalendarExpanded = false
    @State private var relatedPersonID = 0
    @State private var relationPersonQuery = ""
    @State private var showingRelationshipPath = false
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
                    Text(String(localized: "\(tree.int("peopleCount")) 位人物 · \(tree.int("memberCount")) 位已加入成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary)
                    if !tree.text("description").isEmpty { Text(tree.text("description")) }
                    Button("亲缘路径", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        showingRelationshipPath = true
                    }
                    .disabled(people.isEmpty && relationships.isEmpty)
                    if owner {
                        Button(String(localized: "添加家族成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.badge.plus") { openAddPerson() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            if owner && !requests.isEmpty {
                Section(String(localized: "待审核申请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(requests) { request in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(request.text("displayName")).font(.headline)
                            Text(String(localized: "用户中心账号：", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) + request.text("accountName")).font(.caption).foregroundStyle(.secondary)
                            if !request.text("message").isEmpty { Text(request.text("message")) }
                            Picker(String(localized: "关联人物", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: Binding(get: { matches[request.id] ?? 0 }, set: { matches[request.id] = $0 })) {
                                Text(String(localized: "新建本人记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag(0)
                                ForEach(people.filter { !$0.flag("isLinked") }) { person in Text(person.text("displayName") + " #\(person.id)").tag(person.id) }
                            }
                            HStack {
                                Button(String(localized: "通过", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await decide(request, "approve") } }
                                Spacer()
                                Button(String(localized: "拒绝", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { Task { await decide(request, "reject") } }
                            }.disabled(busy)
                        }
                    }
                }
            }
            Section(String(localized: "家族成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                HStack {
                    TextField(String(localized: "按姓名或支系查找", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $query)
                    Button(String(localized: "查找", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await loadPeople() } }.disabled(busy)
                }
                ForEach(people) { person in
                    Button { openPerson(person) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.text("displayName")).font(.headline)
                                Text([person.text("generationLabel"), person.text("branchName")].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                Text([genderLabel(person.text("gender")), birthdayLabel(person)].filter { $0 != String(localized: "未填写", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if person.flag("isSelf") { Text(String(localized: "我", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.teal) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }.foregroundStyle(.primary)
                }
                if hasMore { Text(String(localized: "结果超过 100 位，请输入姓名或支系缩小范围。 ", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: 860).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(tree?.text("name") ?? String(localized: "族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingRelationshipPath) {
            GenealogyPathView(people: people, relationships: relationships)
        }
        .sheet(item: $selected) { person in
            NavigationStack {
                Form {
                    if let editError { Section { Text(editError).foregroundStyle(.red) } }
                    Section(String(localized: "成员资料", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        if householdLinks.contains(where: { $0.int("treeId") == treeID && $0.int("personId") == person.id }) {
                            Text(String(localized: "已关联到‘我的’中的家庭成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.green)
                        }
                        if owner {
                            personEditorFields
                        } else {
                            LabeledContent(String(localized: "姓名", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: person.text("displayName"))
                            if !person.text("generationLabel").isEmpty { LabeledContent(String(localized: "辈分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: person.text("generationLabel")) }
                            if !person.text("branchName").isEmpty { LabeledContent(String(localized: "支系", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: person.text("branchName")) }
                            LabeledContent(String(localized: "性别", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: genderLabel(person.text("gender")))
                            LabeledContent(String(localized: "生日", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: birthdayLabel(person))
                            if !person.text("note").isEmpty { Text(person.text("note")) }
                        }
                    }
                    Section(String(localized: "亲属关系", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        let related = relationships.filter { $0.int("fromPersonId") == person.id || $0.int("toPersonId") == person.id }
                        if related.isEmpty { Text(String(localized: "暂无亲属关系", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                        ForEach(related) { relation in
                            let selectedIsFrom = relation.int("fromPersonId") == person.id
                            let otherID = selectedIsFrom ? relation.int("toPersonId") : relation.int("fromPersonId")
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(relation.text("kind") == "spouse" ? String(localized: "配偶", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : selectedIsFrom ? String(localized: "子女", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "父母", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary)
                                    Button(selectedIsFrom ? relation.text("toName") : relation.text("fromName")) { Task { await selectPerson(otherID) } }
                                }
                                Spacer()
                                if owner { Button(String(localized: "移除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { Task { await remove(relation) } }.disabled(busy) }
                            }
                        }
                    }
                    Section(String(localized: "根据已有关系推导", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        Text(String(localized: "由父母与子女关系自动计算，基础关系变化后会更新；缺少性别和年龄时使用中性称谓。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                            .font(.caption).foregroundStyle(.secondary)
                        if inferenceLoading { ProgressView(String(localized: "正在计算…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                        if let inferenceError { Text(inferenceError).foregroundStyle(.red) }
                        if !inferenceLoading && inferenceError == nil && inferred.isEmpty {
                            Text(String(localized: "暂无可推导的关系", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary)
                        }
                        ForEach(["sibling", "grandparent", "grandchild", "parentSibling", "siblingChild", "cousin"], id: \.self) { kind in
                            let matches = inferred.filter { $0.text("kind") == kind }
                            if !matches.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(inferenceLabel(kind)).font(.caption).foregroundStyle(.secondary)
                                    ForEach(matches) { item in
                                        Button(item.text("displayName")) { Task { await selectPerson(item.int("personId")) } }
                                    }
                                }
                            }
                        }
                    }
                    if owner {
                        Section(String(localized: "为此人添加关系", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                            Picker(String(localized: "关系", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $relationKind) {
                                Text(String(localized: "父母", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("parent")
                                Text(String(localized: "子女", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("child")
                                Text(String(localized: "配偶", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("spouse")
                            }
                            TextField("搜索姓名、支系或辈分", text: $relationPersonQuery)
                            let search = relationPersonQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                            let candidates = people.filter { other in
                                other.id != person.id && (search.isEmpty || other.id == relatedPersonID ||
                                    ["displayName", "branchName", "generationLabel"].contains { other.text($0).localizedCaseInsensitiveContains(search) })
                            }
                            if candidates.isEmpty && !search.isEmpty {
                                Text("没有匹配的家族成员").foregroundStyle(.secondary)
                            }
                            Picker(String(localized: "另一位成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $relatedPersonID) {
                                Text(String(localized: "请选择", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag(0)
                                ForEach(candidates) { other in
                                    let detail = [other.text("branchName"), other.text("generationLabel")].filter { !$0.isEmpty }
                                    Text(([other.text("displayName")] + detail).joined(separator: " · ") + " #\(other.id)").tag(other.id)
                                }
                            }
                            Button(String(localized: "添加关系", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await addRelation(person.id) } }
                                .disabled(busy || relatedPersonID == 0)
                        }
                        Section(String(localized: "邀请本人加入", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                            if person.flag("isLinked") {
                                Text(String(localized: "此人物已绑定用户。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary)
                            } else {
                                Text(String(localized: "链接有效 7 天，仅可使用一次；重新生成会让旧链接失效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                    .font(.caption).foregroundStyle(.secondary)
                                Button(String(localized: "生成邀请链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await createInvitation(person.id) } }.disabled(busy)
                                if let invitationURL {
                                    let label = String(localized: "分享邀请链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
                                    MomentShareLink(url: invitationURL, title: label, label: label)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(person.text("displayName"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if owner { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { selected = nil }.disabled(editBusy) } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                            if owner { Task { await saveEdit(person.id) } }
                            else { selected = nil }
                        }
                        .disabled(editBusy || owner && !personEditorValid)
                    }
                }
                .interactiveDismissDisabled(owner)
            }
        }
        .sheet(isPresented: $showAddPerson) {
            NavigationStack {
                Form {
                    if let editError { Section { Text(editError).foregroundStyle(.red) } }
                    Section(String(localized: "成员资料", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { personEditorFields }
                }
                .navigationTitle(String(localized: "添加家族成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { showAddPerson = false }.disabled(editBusy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await savePerson() } }
                            .disabled(editBusy || !personEditorValid)
                    }
                }
                .interactiveDismissDisabled()
            }
        }
    }
    private var personEditorValid: Bool {
        editName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && birthdaySelectionComplete(editBirthPrecision, editBirthYear, editBirthMonth, editBirthDay)
    }
    @ViewBuilder private var personEditorFields: some View {
        TextField(String(localized: "姓名", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $editName)
        TextField(String(localized: "辈分（可选）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $editGeneration)
        TextField(String(localized: "支系（可选）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $editBranch)
        demographicFields(gender: $editGender, precision: $editBirthPrecision, year: $editBirthYear, month: $editBirthMonth, day: $editBirthDay)
        TextField(String(localized: "备注（仅成员可见）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $editNote, axis: .vertical).lineLimit(2...4)
        Text(String(localized: "点右上角“完成”后自动保存。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .font(.caption).foregroundStyle(.secondary)
    }
    private func load() async {
        do {
            tree = Record(fields: try object(await store.call(base)))
            await loadPeople()
            relationships = try Record.list(await store.call(base + "/relationships"))
            householdLinks = try Record.list(await store.call("/api/family-members/genealogy-links"))
            if let selected { await loadInferred(selected.id) }
            requests = owner ? try Record.list(await store.call(base + "/join-requests")) : []
            error = nil
        } catch is CancellationError {} catch { self.error = momentDisplayError(error) }
    }
    private func loadPeople() async {
        do {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count <= 80 else { throw APIError.message(String(localized: "搜索内容不能超过 80 字", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            let result = try object(await store.call(base + "/people?q=\(genealogyQuery(q))"))
            people = try Record.list(result, key: "people")
            hasMore = result["hasMore"] as? Bool ?? false
            if let selected, let latest = people.first(where: { $0.id == selected.id }) { self.selected = latest }
        } catch { self.error = momentDisplayError(error) }
    }
    private func object(_ value: Any) throws -> [String: Any] {
        guard let result = value as? [String: Any] else { throw APIError.message(String(localized: "服务返回的数据格式不正确。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        return result
    }
    private func mutate(_ path: String, method: String = "POST", body: [String: Any]? = nil) async {
        busy = true; error = nil; defer { busy = false }
        do { _ = try await store.call(path, method: method, body: body); await load() }
        catch { self.error = momentDisplayError(error) }
    }
    private func decide(_ request: Record, _ decision: String) async {
        var body: [String: Any] = ["decision": decision]
        if decision == "approve", let match = matches[request.id], match > 0 { body["personId"] = match }
        await mutate(base + "/join-requests/\(request.id)/decision", body: body)
    }
    private func genderLabel(_ gender: String) -> String {
        switch gender { case "male": return String(localized: "男", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); case "female": return String(localized: "女", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); case "other": return String(localized: "其他", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); default: return String(localized: "未填写", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    private func birthdayLabel(_ person: Record) -> String {
        let year = person.int("birthYear")
        guard year > 0 else { return String(localized: "未填写", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        let month = person.int("birthMonth")
        guard month > 0 else { return String(localized: "\(year)年", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        let day = person.int("birthDay")
        return day > 0 ? String(localized: "\(year)年\(month)月\(day)日", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "\(year)年\(month)月", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func birthdaySelectionComplete(_ precision: String, _ year: String, _ month: String, _ day: String) -> Bool {
        precision == "none" || (!year.isEmpty && (precision == "year" || !month.isEmpty && (precision == "month" || !day.isEmpty)))
    }
    private func calendarDate(_ year: String, _ month: String, _ day: String) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: Date())
        return calendar.date(from: DateComponents(year: Int(year) ?? currentYear, month: Int(month) ?? 1, day: Int(day) ?? 1)) ?? Date()
    }
    private func applyCalendarDate(_ value: Date, precision: String, year: Binding<String>, month: Binding<String>, day: Binding<String>) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: value)
        year.wrappedValue = String(parts.year ?? 1)
        month.wrappedValue = precision == "year" ? "" : String(parts.month ?? 1)
        day.wrappedValue = precision == "date" ? String(parts.day ?? 1) : ""
        birthdayCalendarExpanded = false
    }
    @ViewBuilder private func demographicFields(gender: Binding<String>, precision: Binding<String>, year: Binding<String>, month: Binding<String>, day: Binding<String>) -> some View {
        Picker(String(localized: "性别（可选）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: gender) {
            Text(String(localized: "未填写", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("")
            Text(String(localized: "男", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("male")
            Text(String(localized: "女", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("female")
            Text(String(localized: "其他", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("other")
        }
        Picker(String(localized: "生日精度", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: precision) {
            Text(String(localized: "不填写", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("none")
            Text(String(localized: "仅年份", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("year")
            Text(String(localized: "年和月", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("month")
            Text(String(localized: "完整日期", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("date")
        }
        .onChange(of: precision.wrappedValue) { _, value in
            birthdayCalendarExpanded = false
            if value == "none" { year.wrappedValue = ""; month.wrappedValue = ""; day.wrappedValue = "" }
            else if value == "year" { month.wrappedValue = ""; day.wrappedValue = "" }
            else if value == "month" { day.wrappedValue = "" }
        }
        if precision.wrappedValue != "none" {
            let selection = Binding<Date>(
                get: { calendarDate(year.wrappedValue, month.wrappedValue, day.wrappedValue) },
                set: { applyCalendarDate($0, precision: precision.wrappedValue, year: year, month: month, day: day) }
            )
            DisclosureGroup(String(localized: "从日历选择生日", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isExpanded: $birthdayCalendarExpanded) {
                DatePicker(String(localized: "选择日期", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: selection, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.calendar, Calendar(identifier: .gregorian))
            }
            Text(birthdaySelectionComplete(precision.wrappedValue, year.wrappedValue, month.wrappedValue, day.wrappedValue)
                ? String(localized: "仅保存所选精度，未选定的月日不会补值。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "请在日历中选定生日后保存。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func openPerson(_ person: Record) {
        birthdayCalendarExpanded = false
        editName = person.text("displayName")
        editGeneration = person.text("generationLabel")
        editBranch = person.text("branchName")
        editNote = person.text("note")
        editGender = person.text("gender")
        editBirthYear = person.int("birthYear") == 0 ? "" : String(person.int("birthYear"))
        editBirthMonth = person.int("birthMonth") == 0 ? "" : String(person.int("birthMonth"))
        editBirthDay = person.int("birthDay") == 0 ? "" : String(person.int("birthDay"))
        editBirthPrecision = person.int("birthDay") > 0 ? "date" : person.int("birthMonth") > 0 ? "month" : person.int("birthYear") > 0 ? "year" : "none"
        editError = nil
        relatedPersonID = 0
        relationPersonQuery = ""
        invitationURL = nil
        selected = person
        Task { await loadInferred(person.id) }
    }
    private func openAddPerson() {
        editName = ""
        editGeneration = ""
        editBranch = ""
        editNote = ""
        editGender = ""
        editBirthYear = ""
        editBirthMonth = ""
        editBirthDay = ""
        editBirthPrecision = "none"
        birthdayCalendarExpanded = false
        editError = nil
        showAddPerson = true
    }
    private func inferenceLabel(_ kind: String) -> String {
        switch kind {
        case "sibling": return String(localized: "兄弟姐妹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case "grandparent": return String(localized: "祖辈", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case "grandchild": return String(localized: "孙辈", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case "parentSibling": return String(localized: "父母的兄弟姐妹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case "siblingChild": return String(localized: "兄弟姐妹的子女", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case "cousin": return String(localized: "堂表亲", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        default: return String(localized: "亲属", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }
    private func loadInferred(_ personID: Int) async {
        guard selected?.id == personID else { return }
        inferred = []
        inferenceLoading = true
        inferenceError = nil
        do {
            let values = try Record.list(await store.call(base + "/people/\(personID)/inferred-relationships"))
            if selected?.id == personID { inferred = values; inferenceLoading = false }
        } catch {
            if selected?.id == personID { inferenceError = momentDisplayError(error); inferenceLoading = false }
        }
    }
    private func savePerson() async {
        editBusy = true; editError = nil; defer { editBusy = false }
        let body = personEditorBody()
        do {
            _ = try await store.call(base + "/people", method: "POST", body: body)
            await load()
            showAddPerson = false
        } catch { editError = momentDisplayError(error) }
    }
    private func saveEdit(_ personID: Int) async {
        editBusy = true; editError = nil; defer { editBusy = false }
        let body = personEditorBody()
        do {
            _ = try await store.call(base + "/people/\(personID)", method: "PUT", body: body)
            await load()
            selected = nil
        } catch { editError = momentDisplayError(error) }
    }
    private func personEditorBody() -> [String: Any] {
        ["displayName": editName.trimmingCharacters(in: .whitespacesAndNewlines),
         "generationLabel": editGeneration.trimmingCharacters(in: .whitespacesAndNewlines),
         "branchName": editBranch.trimmingCharacters(in: .whitespacesAndNewlines),
         "note": editNote.trimmingCharacters(in: .whitespacesAndNewlines),
         "gender": editGender, "birthYear": editBirthYear,
         "birthMonth": editBirthMonth, "birthDay": editBirthDay]
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
                throw APIError.message(String(localized: "邀请链接格式不正确", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            invitationURL = url
        } catch { editError = momentDisplayError(error) }
    }
    private func remove(_ relation: Record) async { await mutate(base + "/relationships/\(relation.id)", method: "DELETE") }
    private func selectPerson(_ id: Int) async {
        do { openPerson(Record(fields: try object(await store.call(base + "/people/\(id)")))) }
        catch { self.error = momentDisplayError(error) }
    }
}

private struct GenealogyPathGraph {
    struct Step: Identifiable {
        let id: Int
        let relation: String
    }

    let names: [Int: String]
    let neighbors: [Int: [Step]]

    init(people: [Record], relationships: [Record]) {
        var names: [Int: String] = [:]
        var neighbors: [Int: [Step]] = [:]
        for person in people { names[person.id] = person.text("displayName") }
        for row in relationships {
            let from = row.int("fromPersonId"), to = row.int("toPersonId")
            guard from > 0, to > 0, from != to else { continue }
            let forward: String
            let reverse: String
            switch row.text("kind") {
            case "parent": forward = "子女"; reverse = "父母"
            case "spouse": forward = "配偶"; reverse = "配偶"
            default: continue
            }
            if names[from] == nil { names[from] = row.text("fromName") }
            if names[to] == nil { names[to] = row.text("toName") }
            neighbors[from, default: []].append(Step(id: to, relation: forward))
            neighbors[to, default: []].append(Step(id: from, relation: reverse))
        }
        self.names = names
        self.neighbors = neighbors
    }

    func path(from start: Int, to end: Int) -> [Step]? {
        guard names[start] != nil, names[end] != nil, start != end else { return nil }
        var queue = [start]
        var index = 0
        var visited: Set<Int> = [start]
        var previous: [Int: (person: Int, step: Step)] = [:]
        while index < queue.count {
            let person = queue[index]
            index += 1
            for step in neighbors[person] ?? [] where visited.insert(step.id).inserted {
                previous[step.id] = (person, step)
                if step.id == end {
                    var steps: [Step] = []
                    var cursor = end
                    while let edge = previous[cursor] {
                        steps.append(edge.step)
                        cursor = edge.person
                    }
                    return Array(steps.reversed())
                }
                queue.append(step.id)
            }
        }
        return nil
    }
}

private struct GenealogyPathView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var first: Int?
    @State private var second: Int?
    @State private var choosingFirst: Bool
    @State private var search = ""
    let graph: GenealogyPathGraph

    init(people: [Record], relationships: [Record]) {
        graph = GenealogyPathGraph(people: people, relationships: relationships)
        let me = people.first { $0.flag("isSelf") }?.id
        _first = State(initialValue: me)
        _choosingFirst = State(initialValue: me == nil)
    }

    private var candidates: [Int] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return graph.names.keys.filter { id in
            query.isEmpty || graph.names[id, default: ""].localizedCaseInsensitiveContains(query)
                || String(id).contains(query)
        }.sorted { lhs, rhs in
            let order = graph.names[lhs, default: ""].localizedStandardCompare(graph.names[rhs, default: ""])
            return order == .orderedSame ? lhs < rhs : order == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { choosingFirst = true; search = "" } label: {
                        LabeledContent("起点", value: first.flatMap { graph.names[$0] } ?? "选择人物")
                    }
                    Button { choosingFirst = false; search = "" } label: {
                        LabeledContent("终点", value: second.flatMap { graph.names[$0] } ?? "选择人物")
                    }
                }.buttonStyle(.borderless)

                if let first, let second {
                    Section("已记录的关系路径") {
                        if let steps = graph.path(from: first, to: second) {
                            Label(graph.names[first, default: ""], systemImage: "person.crop.circle.fill")
                            ForEach(steps) { step in
                                LabeledContent(step.relation, value: graph.names[step.id, default: ""])
                            }
                        } else {
                            Text("现有记录中未找到连接这两位人物的关系路径。")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(choosingFirst ? "选择起点" : "选择终点") {
                    let matches = candidates
                    if matches.isEmpty { Text("没有匹配的人物").foregroundStyle(.secondary) }
                    ForEach(Array(matches.prefix(50)), id: \.self) { id in
                        Button {
                            if choosingFirst { first = id; choosingFirst = false }
                            else { second = id }
                            search = ""
                        } label: {
                            LabeledContent(graph.names[id, default: ""], value: "#\(id)")
                        }
                        .disabled(id == (choosingFirst ? second : first))
                    }
                    if matches.count > 50 { Text("输入姓名或编号缩小范围。").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .searchable(text: $search, prompt: "按姓名或编号查找")
            .navigationTitle("亲缘路径")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
