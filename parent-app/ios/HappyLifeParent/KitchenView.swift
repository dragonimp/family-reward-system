import SwiftUI
import AgentIdentity

private func kitchenText(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
}

struct DiningModesView: View {
    let userID: String
    let family: FamilyStore
    @AppStorage private var cooking: Bool

    init(userID: String, family: FamilyStore) {
        self.userID = userID
        self.family = family
        _cooking = AppStorage(wrappedValue: false, "dining.mode.\(DiningAccount.identity(userID))")
    }

    var body: some View {
        ZStack {
            DiningView(userID: userID, family: family, active: !cooking, cooking: $cooking)
                .opacity(cooking ? 0 : 1).allowsHitTesting(!cooking).accessibilityHidden(cooking)
            KitchenView(family: family, active: cooking, cooking: $cooking)
                .opacity(cooking ? 1 : 0).allowsHitTesting(cooking).accessibilityHidden(!cooking)
        }
    }
}

struct DiningModeMenu: View {
    @Binding var cooking: Bool
    let family: FamilyStore
    @State private var beverages = false

    var body: some View {
        Menu {
            Picker(kitchenText("用餐方式"), selection: $cooking) {
                Label(kitchenText("出去吃"), systemImage: "fork.knife").tag(false)
                Label(kitchenText("下厨房"), systemImage: "frying.pan").tag(true)
            }
            Button("整两口", systemImage: "wineglass") { beverages = true }
        } label: {
            Image(systemName: "line.3.horizontal")
                .accessibilityLabel(kitchenText("用餐方式"))
        }.sheet(isPresented: $beverages) { BeverageHome(family: family) }
    }
}

struct KitchenCategory: Decodable, Identifiable {
    let id: String
    let name: String
    let icon: String
}
struct KitchenRecipe: Decodable, Identifiable {
    struct Ingredient: Decodable { let name: String; let quantity: Double; let unit: String }
    struct Step: Decodable, Identifiable {
        let number: Int
        let action: String
        let instruction: String
        let illustrationUrl: String?
        var id: Int { number }
    }
    let recipeId: UUID
    let name: String
    let description: String
    let duration: Int
    let difficulty: String
    let servings: Int
    let ingredients: [Ingredient]
    let preparation: [String]
    let steps: [Step]
    let notes: [String]
    let coverImage: String?
    let shareUrl: String?
    let recipeVersion: Int
    var id: UUID { recipeId }
}

@MainActor private final class KitchenStore: ObservableObject {
    @Published var categories: [KitchenCategory] = []
    @Published var category: String?
    @Published var recipe: KitchenRecipe?
    @Published var busy = false
    @Published var message: String?
    private let family: FamilyStore

    init(family: FamilyStore) { self.family = family }

    func load() async {
        guard categories.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            struct Categories: Decodable { let categories: [KitchenCategory] }
            let response = try await family.call("/api/recipes/categories")
            let result = try JSONDecoder().decode(Categories.self, from: JSONSerialization.data(withJSONObject: response))
            categories = result.categories
            category = nil
            message = categories.isEmpty ? kitchenText("菜谱分类正在准备，请稍后再试。") : nil
        } catch { message = kitchenText("菜谱暂时无法加载，请重试。") }
    }

    func choose() async {
        guard !categories.isEmpty, !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        let period: String
        switch DiningMeal.current() {
        case .breakfast: period = "breakfast"
        case .lunch: period = "lunch"
        case .afternoonTea: period = "afternoonTea"
        case .dinner: period = "dinner"
        }
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "category", value: category == "all" ? "" : (category ?? "")),
                            URLQueryItem(name: "meal", value: period)]
        if let recipe { query.queryItems?.append(URLQueryItem(name: "exclude", value: recipe.id.uuidString)) }
        do {
            let value = try await family.call("/api/recipes/random?" + (query.percentEncodedQuery ?? ""))
            let next = try JSONDecoder().decode(KitchenRecipe.self, from: JSONSerialization.data(withJSONObject: value))
            guard !next.ingredients.isEmpty, !next.steps.isEmpty else {
                message = kitchenText("菜谱资料不完整，请换一道。"); return
            }
            recipe = next
        } catch {
            message = kitchenText("这个分类暂时没有可用菜谱，或网络连接失败。请重试。")
        }
    }
}

private struct KitchenView: View {
    @StateObject private var model: KitchenStore
    @State private var showingRecipe = false
    let active: Bool
    let family: FamilyStore
    @Binding var cooking: Bool
    init(family: FamilyStore, active: Bool, cooking: Binding<Bool>) {
        _model = StateObject(wrappedValue: KitchenStore(family: family))
        self.active = active
        self.family = family
        _cooking = cooking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(kitchenText("今天做什么？")).font(.largeTitle.bold())
                    if model.categories.isEmpty {
                        Button(kitchenText("加载菜谱分类")) { Task { await model.load() } }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(model.categories) { item in
                                let selected = model.category == item.id
                                Button {
                                    model.category = selected ? nil : item.id
                                    model.recipe = nil
                                } label: {
                                    Text(item.icon + " " + item.name).frame(maxWidth: .infinity).padding(14)
                                        .foregroundStyle(.primary)
                                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                                            selected ? Color.gray : Color.gray.opacity(0.3),
                                            style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [5, 4])))
                                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        if model.category == nil {
                            Text(kitchenText("不选分类，随便做一道")).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button { Task { await model.choose() } } label: {
                            Text(kitchenText("随机选一道")).frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    if model.busy { ProgressView() }
                    if let recipe = model.recipe {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(recipe.name).font(.title2.bold())
                            Text("\(recipe.duration) min · \(recipe.difficulty) · \(recipe.servings) " + kitchenText("人份")).foregroundStyle(.secondary)
                            Text(recipe.description)
                            Button(kitchenText("查看做法")) { showingRecipe = true }.buttonStyle(.borderedProminent)
                            Button(kitchenText("换一道")) { Task { await model.choose() } }.buttonStyle(.bordered)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if let message = model.message { Text(message).foregroundStyle(.secondary) }
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(kitchenText("下厨房")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { DiningModeMenu(cooking: $cooking, family: family) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            NavigationLink("我的厨房") { MyKitchenView(family: family) }
                            NavigationLink(kitchenText("健康饮食")) {
                                HealthyEatingView().navigationBarTitleDisplayMode(.inline)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }.accessibilityLabel("更多")
                    }
                }
                .disabled(model.busy)
                .task(id: active) { if active { await model.load() } }
                .sheet(isPresented: $showingRecipe) {
                    if let recipe = model.recipe { KitchenRecipeDetail(recipe: recipe, family: family) }
                }
        }
    }
}

private struct KitchenRecipeDetail: View {
    let recipe: KitchenRecipe
    let family: FamilyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section { NavigationLink("收藏、星标与做菜打卡") { PersonalRecipeView(family: family, item: PersonalRecipe(["id": recipe.id.uuidString, "kind": "public", "name": recipe.name])) } }
                Section {
                    Text(recipe.name).font(.title.bold())
                    recipeImage(recipe.coverImage)
                    Text("\(recipe.duration) min · \(recipe.difficulty) · \(recipe.servings) " + kitchenText("人份"))
                    Text(recipe.description)
                }
                Section(kitchenText("食材")) {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, item in
                        HStack { Text(item.name); Spacer(); Text(item.quantity.formatted() + " " + item.unit).foregroundStyle(.secondary) }
                    }
                }
                Section(kitchenText("准备工作")) {
                    ForEach(Array(recipe.preparation.enumerated()), id: \.offset) { _, item in Text(item) }
                }
                Section(kitchenText("制作步骤")) {
                    ForEach(recipe.steps) { step in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(step.number). " + step.action).font(.headline)
                            recipeImage(step.illustrationUrl)
                            Text(step.instruction)
                            if step.illustrationUrl == nil {
                                Label(kitchenText("步骤插画暂未提供"), systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section(kitchenText("注意事项")) {
                    ForEach(Array(recipe.notes.enumerated()), id: \.offset) { _, item in Text(item) }
                }
            }.navigationTitle(kitchenText("查看做法")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(kitchenText("完成")) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let value = recipe.shareUrl, let url = URL(string: value), url.scheme == "https" {
                            MomentShareLink(url: url, title: recipe.name, label: kitchenText("分享"))
                                .labelStyle(.iconOnly)
                        } else {
                            ShareLink(item: shareText) {
                                Label(kitchenText("分享"), systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                            }
                        }
                    }
                }
        }
    }

    private var shareText: String {
        var lines = [recipe.name, recipe.description, "\(recipe.duration) min · \(recipe.difficulty) · \(recipe.servings) " + kitchenText("人份"), kitchenText("食材")]
        lines += recipe.ingredients.map { "\($0.name) \($0.quantity.formatted()) \($0.unit)" }
        lines += [kitchenText("准备工作")] + recipe.preparation + [kitchenText("制作步骤")]
        lines += recipe.steps.map { "\($0.number). \($0.action)\n\($0.instruction)" }
        lines += [kitchenText("注意事项")] + recipe.notes
        return lines.joined(separator: "\n")
    }

    @ViewBuilder private func recipeImage(_ value: String?) -> some View {
        if let value, let url = URL(string: value), url.scheme == "https" {
            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                .frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct HealthyEatingView: View {
    @State private var day = Date()
    private let plans: [[String]] = [
        [String(localized: "燕麦牛奶碗＋鸡蛋\n主食40克＋牛奶250毫升＋鸡蛋1个＋蔬菜100克。燕麦/小米加水煮熟，馒头蒸热，鸡蛋煮至蛋白蛋黄凝固；吐司按包装即食。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "糙米饭＋香菇鸡肉＋西兰花\n杂粮/糙米60克＋肉或鱼虾120克＋蔬菜250克。米加水煮熟；鱼虾蒸熟、肉切片少油炒熟，蔬菜焯熟或清炒。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "红薯＋番茄豆腐煲\n薯类或玉米200克＋豆腐150克（或肉鱼100克）＋蔬菜250克。薯类蒸至无硬芯，豆腐和蔬菜煮透；禽肉中心至少74℃，鱼肉至少63℃。", bundle: AgentIdentityLanguage.appBundle())],
        [String(localized: "全麦吐司＋鸡蛋＋牛奶\n主食40克＋牛奶250毫升＋鸡蛋1个＋蔬菜100克。燕麦/小米加水煮熟，馒头蒸热，鸡蛋煮至蛋白蛋黄凝固；吐司按包装即食。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "杂粮饭＋清蒸鱼＋油麦菜\n杂粮/糙米60克＋肉或鱼虾120克＋蔬菜250克。米加水煮熟；鱼虾蒸熟、肉切片少油炒熟，蔬菜焯熟或清炒。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "玉米＋香菇豆腐＋青菜\n薯类或玉米200克＋豆腐150克（或肉鱼100克）＋蔬菜250克。薯类蒸至无硬芯，豆腐和蔬菜煮透；禽肉中心至少74℃，鱼肉至少63℃。", bundle: AgentIdentityLanguage.appBundle())],
        [String(localized: "小米粥＋鸡蛋＋牛奶\n主食40克＋牛奶250毫升＋鸡蛋1个＋蔬菜100克。燕麦/小米加水煮熟，馒头蒸热，鸡蛋煮至蛋白蛋黄凝固；吐司按包装即食。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "糙米饭＋瘦牛肉＋彩椒\n杂粮/糙米60克＋肉或鱼虾120克＋蔬菜250克。米加水煮熟；鱼虾蒸熟、肉切片少油炒熟，蔬菜焯熟或清炒。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "蒸土豆＋虾仁＋西兰花\n薯类或玉米200克＋豆腐150克（或肉鱼100克）＋蔬菜250克。薯类蒸至无硬芯，豆腐和蔬菜煮透；禽肉中心至少74℃，鱼肉至少63℃。", bundle: AgentIdentityLanguage.appBundle())],
        [String(localized: "全麦馒头＋牛奶＋鸡蛋\n主食40克＋牛奶250毫升＋鸡蛋1个＋蔬菜100克。燕麦/小米加水煮熟，馒头蒸热，鸡蛋煮至蛋白蛋黄凝固；吐司按包装即食。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "杂粮饭＋去皮鸡腿＋白菜\n杂粮/糙米60克＋肉或鱼虾120克＋蔬菜250克。米加水煮熟；鱼虾蒸熟、肉切片少油炒熟，蔬菜焯熟或清炒。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "红薯＋豆腐＋菠菜\n薯类或玉米200克＋豆腐150克（或肉鱼100克）＋蔬菜250克。薯类蒸至无硬芯，豆腐和蔬菜煮透；禽肉中心至少74℃，鱼肉至少63℃。", bundle: AgentIdentityLanguage.appBundle())],
        [String(localized: "燕麦牛奶碗＋鸡蛋\n主食40克＋牛奶250毫升＋鸡蛋1个＋蔬菜100克。燕麦/小米加水煮熟，馒头蒸热，鸡蛋煮至蛋白蛋黄凝固；吐司按包装即食。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "糙米饭＋清蒸鱼＋西兰花\n杂粮/糙米60克＋肉或鱼虾120克＋蔬菜250克。米加水煮熟；鱼虾蒸熟、肉切片少油炒熟，蔬菜焯熟或清炒。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "玉米＋鸡肉＋番茄\n薯类或玉米200克＋豆腐150克（或肉鱼100克）＋蔬菜250克。薯类蒸至无硬芯，豆腐和蔬菜煮透；禽肉中心至少74℃，鱼肉至少63℃。", bundle: AgentIdentityLanguage.appBundle())],
        [String(localized: "全麦吐司＋牛奶＋鸡蛋\n主食40克＋牛奶250毫升＋鸡蛋1个＋蔬菜100克。燕麦/小米加水煮熟，馒头蒸热，鸡蛋煮至蛋白蛋黄凝固；吐司按包装即食。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "杂粮饭＋虾仁＋油麦菜\n杂粮/糙米60克＋肉或鱼虾120克＋蔬菜250克。米加水煮熟；鱼虾蒸熟、肉切片少油炒熟，蔬菜焯熟或清炒。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "蒸土豆＋豆腐＋香菇\n薯类或玉米200克＋豆腐150克（或肉鱼100克）＋蔬菜250克。薯类蒸至无硬芯，豆腐和蔬菜煮透；禽肉中心至少74℃，鱼肉至少63℃。", bundle: AgentIdentityLanguage.appBundle())],
        [String(localized: "小米粥＋牛奶＋鸡蛋\n主食40克＋牛奶250毫升＋鸡蛋1个＋蔬菜100克。燕麦/小米加水煮熟，馒头蒸热，鸡蛋煮至蛋白蛋黄凝固；吐司按包装即食。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "糙米饭＋瘦牛肉＋白菜\n杂粮/糙米60克＋肉或鱼虾120克＋蔬菜250克。米加水煮熟；鱼虾蒸熟、肉切片少油炒熟，蔬菜焯熟或清炒。", bundle: AgentIdentityLanguage.appBundle()), String(localized: "红薯＋清蒸鱼＋青菜\n薯类或玉米200克＋豆腐150克（或肉鱼100克）＋蔬菜250克。薯类蒸至无硬芯，豆腐和蔬菜煮透；禽肉中心至少74℃，鱼肉至少63℃。", bundle: AgentIdentityLanguage.appBundle())]
    ]
    var body: some View {
        let calendar = Calendar(identifier: .gregorian)
        let index = (calendar.component(.weekday, from: day) + 5) % 7
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "健康饮食", bundle: AgentIdentityLanguage.appBundle())).font(.largeTitle.bold())
            Text(String(localized: "成人控制体重 · 七日轮换食谱 · 当地日期", bundle: AgentIdentityLanguage.appBundle())).foregroundStyle(.secondary)
            DatePicker(String(localized: "日期", bundle: AgentIdentityLanguage.appBundle()), selection: $day, displayedComponents: .date)
            Button(String(localized: "今天", bundle: AgentIdentityLanguage.appBundle())) { day = Date() }
            ForEach(0..<3) { meal in
                Text([String(localized: "早餐", bundle: AgentIdentityLanguage.appBundle()), String(localized: "午餐", bundle: AgentIdentityLanguage.appBundle()), String(localized: "晚餐", bundle: AgentIdentityLanguage.appBundle())][meal]).font(.title2.bold())
                Text(plans[index][meal])
            }
            Text(String(localized: "成人控制体重参考，每人份；不是个性化热量处方。谷物按干重、肉鱼按生的可食部、蔬果按可食部计。按活动量与饥饿程度调整，避免跳餐。另配新鲜水果200克、无糖酸奶150克、无盐坚果10克；奶制品不耐受时按需选择无乳糖产品。注意蛋、奶、小麦、大豆、鱼虾等过敏原。孕哺期及有疾病者需单独制定饮食方案。", bundle: AgentIdentityLanguage.appBundle()))
            Text(String(localized: "少油少盐，以水替代含糖饮料。生熟分开，处理食材前后洗手。食谱为原创搭配，尚待营养师及烹饪复核。", bundle: AgentIdentityLanguage.appBundle()))
            Text(String(localized: "参考：WHO Healthy diet · https://www.who.int/news-room/fact-sheets/detail/healthy-diet", bundle: AgentIdentityLanguage.appBundle())).font(.footnote)
        }.padding(20) }
    }
}

private struct BeverageHome: View {
    let family: FamilyStore
    @Environment(\.dismiss) private var dismiss
    @State private var section = "拍照记一杯"
    @State private var items: [[String: Any]] = []
    @State private var photos: [String] = []
    @State private var recordID = UUID()
    @State private var recognitionID: UUID?
    @State private var name = ""
    @State private var category = "unknown"
    @State private var details: [String: String] = [:]
    @State private var rating = 0
    @State private var note = ""
    @State private var place = ""
    @State private var day = Date()
    @State private var busy = false
    @State private var message = ""
    @State private var query = ""
    @State private var recommendation = 0
    private let fields = [("brand","品牌"),("kind","品类"),("origin","产地"),("producer","生产商"),("size","规格"),("alcoholPercent","酒精度"),("vintage","年份")]
    private var suggestions: [String] {
        let ranked = items.sorted { score($0) > score($1) }.compactMap { $0["name"] as? String }
        return ranked.isEmpty ? ["茉莉花茶", "冰拿铁", "气泡水", "乌龙奶茶"] : ranked
    }
    private func score(_ item: [String: Any]) -> Int {
        let scores = (item["records"] as? [[String: Any]] ?? []).compactMap { $0["rating"] as? Int }
        return (scores.isEmpty ? 0 : scores.reduce(0, +) * 10 / scores.count) + ((item["favorite"] as? Bool == true) ? 10 : 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("整两口", selection: $section) {
                    ForEach(["喝点啥", "拍照记一杯", "我的酒柜", "我的饮品屋"], id: \.self) { Text($0) }
                }
                if section == "喝点啥" {
                    Text(suggestions[recommendation % suggestions.count]).font(.title2)
                    Button("换一杯") { recommendation += 1 }
                } else if section == "拍照记一杯" {
                    KitchenPhotoPicker { data in Task { await add(data) } }.disabled(busy || photos.count >= 6)
                    Text("已添加 \(photos.count) 张照片")
                    TextField("饮品名称", text: $name)
                    Picker("分类", selection: $category) {
                        Text("待确认").tag("unknown")
                        Text("酒类").tag("alcoholic")
                        Text("非酒精").tag("nonalcoholic")
                    }
                    ForEach(fields, id: \.0) { field in
                        TextField(field.1, text: Binding(get: { details[field.0, default: ""] }, set: { details[field.0] = $0 }))
                    }
                    Picker("评分", selection: $rating) {
                        Text("不评分").tag(0)
                        ForEach(1...5, id: \.self) { Text(String(repeating: "★", count: $0)).tag($0) }
                    }
                    TextField("一句话评价", text: $note)
                    TextField("饮用地点", text: $place)
                    DatePicker("饮用日期", selection: $day, displayedComponents: .date)
                    if items.contains(where: { matches($0) }) { Text("已有同款档案，将关联本次记录。") }
                    Button("确认归档") { Task { await save() } }.disabled(busy)
                } else {
                    TextField("搜索名称、品牌、品类", text: $query)
                    ForEach(visible, id: \.id) { profile in
                        DisclosureGroup(profile.data["name"] as? String ?? "饮品") {
                            if profile.data["category"] as? String == "unknown" { Text("分类待确认").font(.caption) }
                            let favorite = profile.data["favorite"] as? Bool == true
                            Button(favorite ? "取消收藏" : "收藏") { Task { await run {
                                _ = try await family.call("/api/beverages/\(profile.id)/favorite", method: "PUT", body: ["favorite": !favorite])
                                try await load()
                            } } }
                            ForEach(records(profile.data), id: \.id) { record in
                                Text([record.data["consumedOn"] as? String, record.data["note"] as? String, record.data["place"] as? String].compactMap { $0 }.joined(separator: " · "))
                                if let score = record.data["rating"] as? Int, (1...5).contains(score) { Text(String(repeating: "★", count: score)) }
                                Button("编辑记录") { edit(profile.data, record: record) }
                                Button("删除记录", role: .destructive) { pendingDeletion = record.id }
                            }
                        }
                    }
                }
                if busy { ProgressView() }
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            }.navigationTitle("整两口").toolbar { Button("关闭") { dismiss() } }
            .task { await run { try await load() } }
            .confirmationDialog("删除这条饮用记录？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
                if let id = pendingDeletion {
                    Button("删除", role: .destructive) { Task { await run {
                        _ = try await family.call("/api/beverages/records/\(id)", method: "DELETE")
                        try await load()
                    } } }
                }
            }
        }
    }
    @State private var pendingDeletion: String?
    @State private var profileID: String?
    private struct Row: Identifiable { let id: String; let data: [String: Any] }
    private func rows(_ data: [[String: Any]]) -> [Row] { data.compactMap { row in (row["id"] as? String).map { Row(id: $0, data: row) } } }
    private var visible: [Row] {
        let type = section == "我的酒柜" ? "alcoholic" : "nonalcoholic"
        return rows(items.filter { item in
            let category = item["category"] as? String
            return (category == type || (type == "nonalcoholic" && category == "unknown")) && (query.isEmpty ||
                ["name", "brand", "kind"].contains { (item[$0] as? String ?? "").localizedCaseInsensitiveContains(query) })
        })
    }
    private func records(_ item: [String: Any]) -> [Row] { rows(item["records"] as? [[String: Any]] ?? []) }
    private var formatter: DateFormatter {
        let value = DateFormatter(); value.calendar = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX"); value.dateFormat = "yyyy-MM-dd"; return value
    }
    private func edit(_ profile: [String: Any], record: Row) {
        guard let id = UUID(uuidString: record.id) else { return }
        recognitionID = nil
        recordID = id; profileID = profile["id"] as? String
        apply(profile)
        photos = record.data["photoIds"] as? [String] ?? []
        rating = record.data["rating"] as? Int ?? 0
        note = record.data["note"] as? String ?? ""; place = record.data["place"] as? String ?? ""
        day = formatter.date(from: record.data["consumedOn"] as? String ?? "") ?? Date()
        section = "拍照记一杯"
    }
    private func apply(_ draft: [String: Any], onlyEmpty: Bool = false) {
        if !onlyEmpty || name.isEmpty { name = draft["name"] as? String ?? "" }
        if !onlyEmpty || category == "unknown" { category = draft["category"] as? String ?? "unknown" }
        for (key, _) in fields where !onlyEmpty || details[key, default: ""].isEmpty {
            details[key] = draft[key] as? String ?? (draft[key] as? NSNumber)?.stringValue ?? ""
        }
    }
    private func matches(_ item: [String: Any]) -> Bool {
        ["name", "brand", "producer", "vintage"].allSatisfy { key in
            let left = key == "name" ? name : details[key, default: ""]
            let right = item[key] as? String ?? (item[key] as? NSNumber)?.stringValue ?? ""
            return left.trimmingCharacters(in: .whitespacesAndNewlines).compare(right, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
        }
    }
    private func load() async throws {
        let result = try await family.call("/api/beverages") as? [String: Any]
        items = result?["items"] as? [[String: Any]] ?? []
    }
    private func run(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; message = ""; defer { busy = false }
        do { try await work() } catch { message = error.localizedDescription }
    }
    private func add(_ bytes: Data) async {
        await run {
            guard photos.count < 6 else { return }
            let media = UUID().uuidString, task = UUID()
            _ = try await family.call("/api/kitchen/media", method: "POST", body: ["id":media,"purpose":"recipe","base64":bytes.base64EncodedString()])
            photos.append(media)
            recognitionID = task
            message = "正在识别，可先手动填写并归档。"
            Task { await recognize(task, media: media) }
        }
    }
    private func recognize(_ task: UUID, media: String) async {
        let route = "/api/beverages/recognitions/\(task.uuidString)"
        do {
            _ = try await family.call(route, method: "POST", body: ["mediaId":media])
            for _ in 0..<95 {
                guard recognitionID == task else { return }
                let row = try await family.call(route) as? [String: Any]
                guard recognitionID == task else { return }
                if row?["state"] as? String == "completed", let draft = row?["result"] as? [String: Any] {
                    apply(draft, onlyEmpty: true)
                    message = (draft["name"] as? String ?? "").isEmpty
                        ? "未识别出饮品名称，请输入名称后归档。" : "请确认识别结果，可手动修改。"
                    return
                }
                if row?["state"] as? String == "failed" { break }
                try await Task.sleep(for: .seconds(2))
            }
        } catch {
            // The uploaded photo is still available for manual archiving.
        }
        if recognitionID == task { message = "识别未完成，照片已保留，请输入饮品名称后归档。" }
    }
    private func save() async {
        await run {
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { message = "请填写饮品名称。"; return }
            var draft: [String: Any] = ["name":title, "category":category]
            for (key, value) in details where !value.isEmpty {
                if key == "alcoholPercent" {
                    guard let number = Double(value), number.isFinite, (0...100).contains(number) else { message = "请输入有效酒精度。"; return }
                    draft[key] = number
                } else if key == "vintage" {
                    guard let year = Int(value), (1000...9999).contains(year) else { message = "请输入有效年份。"; return }
                    draft[key] = year
                } else { draft[key] = value }
            }
            var body: [String: Any] = ["beverage":draft,"consumedOn":formatter.string(from: day),"note":note,"place":place,"photoIds":photos]
            if let profileID { body["beverageId"] = profileID }
            if rating > 0 { body["rating"] = rating }
            recognitionID = nil
            _ = try await family.call("/api/beverages/records/\(recordID.uuidString)", method: "PUT", body: body)
            section = category == "alcoholic" ? "我的酒柜" : "我的饮品屋"
            name = ""; category = "unknown"; details = [:]; photos = []; rating = 0
            note = ""; place = ""; day = Date(); profileID = nil; recordID = UUID()
            try await load()
        }
    }
}
