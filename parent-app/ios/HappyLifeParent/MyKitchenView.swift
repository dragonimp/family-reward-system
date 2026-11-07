import SwiftUI
import PhotosUI

// Personal kitchen deliberately uses authenticated media, never public recipe share URLs.
struct PersonalRecipe: Identifiable {
    var id: String
    var kind: String
    var name: String
    var favorite = false
    var starred = false
    var mediaID: String?
    var cover: String?
    var madeCount = 0
    init(_ value: [String: Any]) {
        id = value["id"] as? String ?? value["recipeId"] as? String ?? ""
        kind = value["kind"] as? String ?? "public"
        name = value["name"] as? String ?? "菜谱"
        favorite = value["favorite"] as? Bool ?? false
        starred = value["starred"] as? Bool ?? false
        madeCount = value["madeCount"] as? Int ?? 0
        mediaID = value["originalMediaId"] as? String
        cover = (value["recipe"] as? [String: Any])?["coverImage"] as? String
    }
}
struct KitchenIngredientDraft: Identifiable {
    let id = UUID()
    var name = "", quantity = "", unit = ""
}
struct KitchenStepDraft: Identifiable {
    let id = UUID()
    var action = "", ingredients = "", duration = "", heat = "", instruction = "", notes = ""
}
struct KitchenDraft {
    var id = UUID().uuidString, version = 0
    var name = "", duration = "", servings = "", difficulty = "", preparation = "", notes = "", source = ""
    var ingredients = [KitchenIngredientDraft()]
    var steps = [KitchenStepDraft()]
    var mediaID: String?, recognitionID: String?
    var uncertainty = ""
    init() {}
    init(_ meta: [String: Any]) {
        self.init()
        let recipe = meta["recipe"] as? [String: Any] ?? meta["draft"] as? [String: Any] ?? [:]
        name = recipe["name"] as? String ?? ""
        id = recipe["recipeId"] as? String ?? id
        version = meta["version"] as? Int ?? 0
        func text(_ value: Any?) -> String { guard let value, !(value is NSNull) else { return "" }; return String(describing: value) }
        duration = text(recipe["duration"]); servings = text(recipe["servings"]); difficulty = text(recipe["difficulty"])
        preparation = (recipe["preparation"] as? [String] ?? []).joined(separator: "\n")
        notes = (recipe["notes"] as? [String] ?? []).joined(separator: "\n")
        ingredients = (recipe["ingredients"] as? [[String: Any]] ?? []).map { KitchenIngredientDraft(name: text($0["name"]), quantity: text($0["quantity"]), unit: text($0["unit"])) }
        steps = (recipe["steps"] as? [[String: Any]] ?? []).map { KitchenStepDraft(action: text($0["action"]), ingredients: ($0["ingredients"] as? [String] ?? []).joined(separator: "、"), duration: text($0["duration"]), heat: text($0["heat"]), instruction: text($0["instruction"]), notes: text($0["notes"])) }
        if ingredients.isEmpty { ingredients = [KitchenIngredientDraft()] }; if steps.isEmpty { steps = [KitchenStepDraft()] }
        mediaID = meta["originalMediaId"] as? String; recognitionID = meta["recognitionId"] as? String
        source = meta["sourceText"] as? String ?? ""
        uncertainty = (meta["uncertainFields"] as? [String] ?? []).joined(separator: "、")
    }
    var payload: [String: Any] {
        func lines(_ text: String) -> [String] { text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        let recipe: [String: Any] = ["name": name, "duration": Int(duration).map { $0 as Any } ?? NSNull(), "servings": Int(servings).map { $0 as Any } ?? NSNull(), "difficulty": difficulty, "ingredients": ingredients.map { ["name": $0.name, "quantity": $0.quantity, "unit": $0.unit] }, "preparation": lines(preparation), "notes": lines(notes), "steps": steps.enumerated().map { index, step in ["number": index + 1, "action": step.action, "ingredients": step.ingredients.components(separatedBy: "、").filter { !$0.isEmpty }, "duration": step.duration, "heat": step.heat, "instruction": step.instruction, "notes": step.notes] as [String: Any] }]
        return ["recipe": recipe, "version": version, "confirmed": true, "sourceText": source, "originalMediaId": mediaID as Any? ?? NSNull(), "recognitionId": recognitionID as Any? ?? NSNull()]
    }
}

struct MyKitchenView: View {
    let family: FamilyStore
    var body: some View {
        List {
            NavigationLink("我的菜谱") { PersonalRecipesView(family: family) }
            NavigationLink("做过的菜") { CookingHistoryView(family: family) }
        }.navigationTitle("我的厨房").navigationBarTitleDisplayMode(.inline)
    }
}
struct PersonalRecipesView: View {
    let family: FamilyStore
    @State private var items: [PersonalRecipe] = []
    @State private var filter = ""
    @State private var search = ""
    @State private var message = ""
    @State private var uploading = false
    var body: some View {
        List {
            Picker("分类", selection: $filter) { Text("全部").tag(""); Text("星标常用").tag("starred"); Text("我上传的").tag("uploaded") }.pickerStyle(.segmented)
            ForEach(items) { item in
                NavigationLink { PersonalRecipeView(family: family, item: item) } label: {
                    HStack {
                        if let media = item.mediaID { KitchenPrivateImage(family: family, id: media).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10)) }
                        else if let cover = item.cover, let url = URL(string: cover), url.scheme == "https" { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "fork.knife") }.frame(width: 64, height: 64) }
                        VStack(alignment: .leading, spacing: 5) { Text(item.name); Text("\(item.starred ? "★ · " : "")已做 \(item.madeCount) 次").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if items.isEmpty { Text("还没有菜谱，可以上传、手动创建或收藏公共菜谱。").foregroundStyle(.secondary) }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
        }.navigationTitle("我的菜谱").searchable(text: $search, prompt: "搜索菜谱")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("上传菜谱", systemImage: "plus") { uploading = true } } }
            .sheet(isPresented: $uploading, onDismiss: { Task { await load() } }) { NavigationStack { KitchenEditor(family: family) } }
            .task(id: filter + search) { await load() }.onAppear { Task { await load() } }.refreshable { await load() }
    }
    private func load() async {
        do {
            var q = URLComponents(); q.queryItems = [URLQueryItem(name: "filter", value: filter), URLQueryItem(name: "q", value: search)]
            let data = try await family.call("/api/kitchen/recipes?" + (q.percentEncodedQuery ?? "")) as? [String: Any]
            items = (data?["items"] as? [[String: Any]] ?? []).map(PersonalRecipe.init); message = ""
        } catch { message = error.localizedDescription }
    }
}
struct KitchenPrivateImage: View {
    let family: FamilyStore
    let id: String
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() } else { Image(systemName: "photo").foregroundStyle(.secondary) } }
            .frame(maxHeight: 240).task(id: id) { image = try? await family.authenticatedImage("/api/kitchen/media/" + id) }
    }
}
struct PersonalRecipeView: View {
    let family: FamilyStore
    let item: PersonalRecipe
    @Environment(\.dismiss) private var dismiss
    @State private var meta: [String: Any] = [:]
    @State private var draft = KitchenDraft()
    @State private var editing = false
    @State private var checkin = false
    @State private var deleting = false
    @State private var message = ""
    var body: some View {
        List {
            Section {
                Text(draft.name).font(.title2.bold())
                if let media = draft.mediaID { KitchenPrivateImage(family: family, id: media) }
                Text("已做 \(meta["madeCount"] as? Int ?? 0) 次").foregroundStyle(.secondary)
                Button(meta["starred"] as? Bool == true ? "★ 取消星标" : "☆ 星标常用") { Task { await relation(star: true) } }
                if item.kind == "public" { Button(meta["favorite"] as? Bool == true ? "取消收藏" : "收藏菜谱") { Task { await relation(star: false) } } }
                Button("做菜打卡", systemImage: "camera") { checkin = true }
                NavigationLink("做菜历史") { CookingHistoryView(family: family, recipeID: item.id) }
            }
            Section("食材") { ForEach(draft.ingredients) { Text("\($0.name)  \($0.quantity) \($0.unit)") } }
            Section("准备工作") { Text(draft.preparation.isEmpty ? "未提供" : draft.preparation) }
            Section("制作步骤") { ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 6) { Text("\(index + 1). " + step.action).font(.headline); Text(step.instruction); Text([step.ingredients, step.duration, step.heat, step.notes].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            } }
            Section("注意事项") { Text(draft.notes.isEmpty ? "请核对食材用量、熟度和食品安全。" : draft.notes) }
            if !draft.source.isEmpty { Section("来源") { Text(draft.source) } }
            if item.kind == "private" { Section { Button("编辑菜谱") { editing = true }; Button("删除菜谱", role: .destructive) { deleting = true } } }
            if !message.isEmpty { Text(message) }
        }.navigationTitle(item.name).navigationBarTitleDisplayMode(.inline).task { await load() }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { NavigationStack { KitchenEditor(family: family, initial: draft) } }
            .sheet(isPresented: $checkin, onDismiss: { Task { await load() } }) { NavigationStack { CookingCheckinEditor(family: family, selected: item) } }
            .confirmationDialog("删除菜谱？做菜历史仍保留。", isPresented: $deleting) { Button("删除", role: .destructive) { Task { do { _ = try await family.call("/api/kitchen/recipes/" + item.id, method: "DELETE"); dismiss() } catch { message = error.localizedDescription } } } }
    }
    private func load() async { do { meta = try await family.call("/api/kitchen/recipes/\(item.id)?kind=\(item.kind)") as? [String: Any] ?? [:]; draft = KitchenDraft(meta) } catch { message = error.localizedDescription } }
    private func relation(star: Bool) async {
        do { _ = try await family.call("/api/kitchen/recipes/\(item.id)/relationship", method: "PUT", body: ["kind": item.kind, "favorite": star ? (meta["favorite"] as? Bool ?? false) : !(meta["favorite"] as? Bool ?? false), "starred": star ? !(meta["starred"] as? Bool ?? false) : (meta["starred"] as? Bool ?? false)]); await load() } catch { message = error.localizedDescription }
    }
}

// Shared capture surface: the existing app camera and PhotosPicker, with JPEG normalization.
struct KitchenPhotoPicker: View {
    let onImage: (Data) -> Void
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Button("拍照", systemImage: "camera") { camera = true }; Spacer(); PhotosPicker(selection: $photo, matching: .images) { Label("从相册选择", systemImage: "photo") } }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.secondary) }
        }.fullScreenCover(isPresented: $camera) { DearCamera(mode: .photo) { result in
            camera = false
            switch result { case .success(let value): if let value { defer { try? FileManager.default.removeItem(at: value.0) }; if let data = try? Data(contentsOf: value.0) { accept(data) } }; case .failure: error = "无法拍照，请检查相机权限或从相册选择。" }
        }.ignoresSafeArea() }
            .onChange(of: photo) { _, next in Task { if let data = try? await next?.loadTransferable(type: Data.self) { accept(data) } else { error = "无法读取图片，请重试。" } } }
    }
    private func accept(_ data: Data) {
        guard data.count <= 30 * 1024 * 1024, let image = UIImage(data: data), image.size.width > 0 else { error = "请选择30MB以内的有效图片。"; return }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: CGSize(width: image.size.width * scale, height: image.size.height * scale), format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))) }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.85), jpeg.count <= 8 * 1024 * 1024 else { error = "图片过大，请重试。"; return }; error = ""; onImage(jpeg)
    }
}
struct KitchenEditor: View {
    let family: FamilyStore
    var initial: KitchenDraft = KitchenDraft()
    @Environment(\.dismiss) private var dismiss
    @State private var draft = KitchenDraft()
    @State private var busy = false
    @State private var confirmed = false
    @State private var message = ""
    @State private var recent: [[String: Any]] = []
    @State private var taskID: String?
    @State private var recognizedDraft: KitchenDraft?
    @State private var pendingPhoto: Data?
    @State private var pendingMediaID = UUID().uuidString
    var body: some View {
        Form {
            Section("拍照或相册识别，也可直接手动填写") {
                KitchenPhotoPicker { data in pendingPhoto = data; pendingMediaID = UUID().uuidString }
                if pendingPhoto != nil { Button("识别所选图片") { Task { await recognize() } } }
                if let media = draft.mediaID { KitchenPrivateImage(family: family, id: media) }
                if let taskID { Text("识别任务已保存，离开页面后仍会继续。").font(.caption); Button("查询识别结果") { Task { await poll(taskID) } } }
                ForEach(recent.indices, id: \.self) { index in let row = recent[index]
                    Button("识别记录 · \(row["state"] as? String ?? "")") { if let id = row["id"] as? String { taskID = id; Task { await poll(id) } } }
                }
                if let recognizedDraft { Button("应用识别结果（替换当前填写内容）") { draft = recognizedDraft; self.recognizedDraft = nil; confirmed = false } }
                if !draft.uncertainty.isEmpty { Text("待确认：" + draft.uncertainty).foregroundStyle(.orange) }
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            }
            Section("菜谱资料") {
                TextField("菜名", text: $draft.name)
                TextField("预计分钟数（未知留空）", text: $draft.duration).keyboardType(.numberPad)
                TextField("人数（未知留空）", text: $draft.servings).keyboardType(.numberPad)
                TextField("难度（未知留空）", text: $draft.difficulty)
                TextField("来源及使用授权说明", text: $draft.source, axis: .vertical)
            }
            Section("食材与用量（未知留空）") {
                ForEach($draft.ingredients) { $item in VStack { TextField("食材", text: $item.name); HStack { TextField("用量", text: $item.quantity); TextField("单位", text: $item.unit) } } }.onDelete { draft.ingredients.remove(atOffsets: $0) }
                Button("添加食材") { draft.ingredients.append(KitchenIngredientDraft()) }
            }
            Section("准备工作 · 每行一项") { TextEditor(text: $draft.preparation).frame(minHeight: 70) }
            Section("制作步骤 · 可拖动排序") {
                ForEach($draft.steps) { $step in VStack(alignment: .leading, spacing: 8) {
                    TextField("操作名称", text: $step.action)
                    TextField("操作说明（必填）", text: $step.instruction, axis: .vertical)
                    TextField("涉及食材，用、分隔", text: $step.ingredients)
                    HStack { TextField("时间", text: $step.duration); TextField("火候", text: $step.heat) }
                    TextField("注意事项", text: $step.notes, axis: .vertical)
                }.padding(.vertical, 4) }.onDelete { draft.steps.remove(atOffsets: $0) }.onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                Button("添加步骤") { draft.steps.append(KitchenStepDraft()) }
            }
            Section("注意事项 · 每行一项") { TextEditor(text: $draft.notes).frame(minHeight: 70) }
            Section {
                Toggle("我已核对食材、步骤、火候及安全提示", isOn: $confirmed)
                Text("仅保存为个人私有菜谱，不自动公开。AI 识别内容需要逐项确认。").font(.caption).foregroundStyle(.secondary)
                Button("保存到我的菜谱") { Task { await save() } }.disabled(!confirmed || busy)
            }
        }.navigationTitle(initial.version == 0 ? "上传菜谱" : "编辑菜谱").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            .disabled(busy).overlay { if busy { ProgressView() } }
            .task { draft = initial; if let data = try? await family.call("/api/kitchen/recognitions") as? [String: Any] { recent = data["items"] as? [[String: Any]] ?? [] } }
            .task(id: taskID) { guard let id = taskID else { return }; while !Task.isCancelled { await poll(id); if taskID == nil { break }; try? await Task.sleep(for: .seconds(4)) } }
    }
    private func recognize() async {
        guard let pendingPhoto else { return }; busy = true; defer { busy = false }
        do {
            _ = try await family.call("/api/kitchen/media", method: "POST", body: ["id": pendingMediaID, "purpose": "recipe", "base64": pendingPhoto.base64EncodedString()])
            draft.mediaID = pendingMediaID
            let id = UUID().uuidString
            _ = try await family.call("/api/kitchen/recognitions", method: "POST", body: ["id": id, "mediaId": pendingMediaID]); taskID = id; message = "正在识别，可先填写或稍后从识别记录继续。"
        } catch { message = error.localizedDescription }
    }
    private func poll(_ id: String) async {
        do {
            guard let row = try await family.call("/api/kitchen/recognitions/" + id) as? [String: Any] else { return }
            switch row["state"] as? String {
            case "completed":
                if let result = row["result"] as? [String: Any] { var next = KitchenDraft(result); next.id = draft.id; next.version = draft.version; next.source = draft.source; next.mediaID = row["mediaId"] as? String; next.recognitionID = id; recognizedDraft = next; message = "识别完成，点击应用结果后逐项核对；缺失信息请手动补充。" }; taskID = nil
            case "failed": message = row["error"] as? String ?? "识别失败，可以重试或手动填写。"; taskID = nil
            default: message = "识别处理中，文字填写仍可使用。"
            }
        } catch { message = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            if let pendingPhoto, draft.mediaID != pendingMediaID {
                _ = try await family.call("/api/kitchen/media", method: "POST", body: ["id": pendingMediaID, "purpose": "recipe", "base64": pendingPhoto.base64EncodedString()]); draft.mediaID = pendingMediaID; draft.recognitionID = nil
            }
            _ = try await family.call("/api/kitchen/recipes/" + draft.id, method: "PUT", body: draft.payload); dismiss()
        } catch { message = error.localizedDescription }
    }
}
struct CookingCheckinEditor: View {
    let family: FamilyStore
    var selected: PersonalRecipe?
    @Environment(\.dismiss) private var dismiss
    @State private var options: [PersonalRecipe] = []
    @State private var recipeID = ""
    @State private var day = Date()
    @State private var note = ""
    @State private var message = ""
    @State private var photo: Data?
    @State private var actionID = UUID().uuidString
    @State private var mediaID = UUID().uuidString
    @State private var busy = false
    @State private var creating = false
    var body: some View {
        Form {
            Section("关联菜谱") { Picker("菜谱", selection: $recipeID) { Text("请选择").tag(""); ForEach(options) { Text($0.name).tag($0.id) } }; Button("创建个人菜谱") { creating = true } }
            Section("成品照片") { KitchenPhotoPicker { photo = $0; mediaID = UUID().uuidString; actionID = UUID().uuidString }; if let photo, let image = UIImage(data: photo) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200) } }
            DatePicker("制作日期", selection: $day, displayedComponents: .date)
            TextField("备注", text: $note, axis: .vertical)
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            Button("完成打卡") { Task { await save() } }.disabled(busy || photo == nil || recipeID.isEmpty)
        }.navigationTitle("做菜打卡").toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
            .task { recipeID = selected?.id ?? ""; await load() }
            .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) { NavigationStack { KitchenEditor(family: family) } }
            .onChange(of: day) { _, _ in actionID = UUID().uuidString }.onChange(of: note) { _, _ in actionID = UUID().uuidString }.onChange(of: recipeID) { _, _ in actionID = UUID().uuidString }
            .disabled(busy)
    }
    private func load() async { do { let value = try await family.call("/api/kitchen/catalog") as? [String: Any]; options = (value?["items"] as? [[String: Any]] ?? []).map(PersonalRecipe.init) } catch { message = error.localizedDescription } }
    private func save() async {
        guard let photo, let recipe = options.first(where: { $0.id == recipeID }) else { return }; busy = true; defer { busy = false }
        do {
            _ = try await family.call("/api/kitchen/media", method: "POST", body: ["id": mediaID, "purpose": "checkin", "base64": photo.base64EncodedString()])
            let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
            _ = try await family.call("/api/kitchen/checkins/" + actionID, method: "PUT", body: ["recipeId": recipe.id, "kind": recipe.kind, "cookedOn": formatter.string(from: day), "mediaId": mediaID, "note": note]); dismiss()
        } catch { message = error.localizedDescription }
    }
}
struct CookingHistoryView: View {
    let family: FamilyStore
    var recipeID: String? = nil
    @State private var rows: [[String: Any]] = []
    @State private var cooked: [[String: Any]] = []
    @State private var message = ""
    @State private var adding = false
    @State private var linkID: String?
    @State private var catalog: [PersonalRecipe] = []
    var body: some View {
        List {
            if recipeID == nil { Section("累计制作") { ForEach(cooked.indices, id: \.self) { i in Text("\(cooked[i]["name"] as? String ?? "菜谱") · \(cooked[i]["madeCount"] as? Int ?? 0) 次") } } }
            Section("做菜记录") { ForEach(rows.indices, id: \.self) { i in let row = rows[i]
                VStack(alignment: .leading, spacing: 8) {
                    Text(row["name"] as? String ?? "待关联菜谱").font(.headline)
                    Text(row["cookedOn"] as? String ?? "").font(.caption).foregroundStyle(.secondary)
                    if let media = row["mediaId"] as? String { KitchenPrivateImage(family: family, id: media) }
                    Text(row["note"] as? String ?? "")
                    Button("关联菜谱") { linkID = row["id"] as? String }
                    Button("删除打卡", role: .destructive) { Task { if let id = row["id"] as? String { do { _ = try await family.call("/api/kitchen/checkins/" + id, method: "DELETE"); await load() } catch { message = error.localizedDescription } } } }
                }
            } }
            if rows.isEmpty { Text("还没有做菜打卡记录。").foregroundStyle(.secondary) }
            if !message.isEmpty { Text(message) }
        }.navigationTitle("做过的菜").toolbar { Button("拍照打卡", systemImage: "camera") { adding = true } }.task { await load() }.refreshable { await load() }
            .sheet(isPresented: $adding, onDismiss: { Task { await load() } }) { NavigationStack { CookingCheckinEditor(family: family) } }
            .sheet(isPresented: Binding(get: { linkID != nil }, set: { if !$0 { linkID = nil } })) { NavigationStack { List(catalog) { recipe in Button(recipe.name) { Task { do { if let id = linkID { _ = try await family.call("/api/kitchen/checkins/\(id)/recipe", method: "PATCH", body: ["recipeId": recipe.id, "kind": recipe.kind]); linkID = nil; await load() } } catch { message = error.localizedDescription } } } }.navigationTitle("关联已有菜谱").toolbar { Button("取消") { linkID = nil } } } }
    }
    private func load() async {
        do {
            let history = try await family.call("/api/kitchen/checkins") as? [String: Any]
            rows = (history?["items"] as? [[String: Any]] ?? []).filter { recipeID == nil || ($0["recipeId"] as? String)?.lowercased() == recipeID?.lowercased() }
            let totals = try await family.call("/api/kitchen/cooked") as? [String: Any]; cooked = totals?["items"] as? [[String: Any]] ?? []
            let choices = try await family.call("/api/kitchen/catalog") as? [String: Any]; catalog = (choices?["items"] as? [[String: Any]] ?? []).map(PersonalRecipe.init)
        } catch { message = error.localizedDescription }
    }
}
