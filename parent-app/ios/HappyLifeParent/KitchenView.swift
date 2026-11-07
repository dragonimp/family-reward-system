import SwiftUI
import AgentIdentity

private func kitchenText(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
}

struct DiningModesView: View {
    let userID: String
    let family: FamilyStore
    @State private var cooking = false

    var body: some View {
        VStack(spacing: 0) {
            Picker(kitchenText("用餐方式"), selection: $cooking) {
                Text(kitchenText("出去吃")).tag(false)
                Text(kitchenText("下厨房")).tag(true)
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
            ZStack {
                DiningView(userID: userID, family: family)
                    .opacity(cooking ? 0 : 1).allowsHitTesting(!cooking).accessibilityHidden(cooking)
                KitchenView(family: family, active: cooking)
                    .opacity(cooking ? 1 : 0).allowsHitTesting(cooking).accessibilityHidden(!cooking)
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
    init(family: FamilyStore, active: Bool) { _model = StateObject(wrappedValue: KitchenStore(family: family)); self.active = active }

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
                .disabled(model.busy)
                .task(id: active) { if active { await model.load() } }
                .sheet(isPresented: $showingRecipe) {
                    if let recipe = model.recipe { KitchenRecipeDetail(recipe: recipe) }
                }
        }
    }
}

private struct KitchenRecipeDetail: View {
    let recipe: KitchenRecipe
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                .toolbar { Button(kitchenText("完成")) { dismiss() } }
        }
    }

    @ViewBuilder private func recipeImage(_ value: String?) -> some View {
        if let value, let url = URL(string: value), url.scheme == "https" {
            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                .frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
