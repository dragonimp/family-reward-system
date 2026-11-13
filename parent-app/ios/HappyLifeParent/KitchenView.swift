import SwiftUI
import AgentIdentity

private func kitchenText(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
}

struct DiningModesView: View {
    let userID: String
    let family: FamilyStore
    @State private var cooking = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker(kitchenText("用餐方式"), selection: $cooking) {
                Text(kitchenText("出去吃")).tag(0)
                Text(kitchenText("下厨房")).tag(1)
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
            ZStack {
                DiningView(userID: userID, family: family)
                    .opacity(cooking == 0 ? 1 : 0).allowsHitTesting(cooking == 0).accessibilityHidden(cooking != 0)
                KitchenView(family: family, active: cooking == 1)
                    .opacity(cooking == 1 ? 1 : 0).allowsHitTesting(cooking == 1).accessibilityHidden(cooking != 1)
            }
        }
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
    init(family: FamilyStore, active: Bool) { _model = StateObject(wrappedValue: KitchenStore(family: family)); self.active = active; self.family = family }

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
