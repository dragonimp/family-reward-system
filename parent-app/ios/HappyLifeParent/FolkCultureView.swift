import SwiftUI

struct FolkCultureView: View {
    let title: String
    @State private var date = Date()
    @State private var first = 0
    @State private var second = 0
    @State private var surname = ""
    @State private var given = ""

    private let animals = Array("鼠牛虎兔龙蛇马羊猴鸡狗猪")
    private let harmony: Set<[Int]> = [[0, 1], [2, 11], [3, 10], [4, 9], [5, 8], [6, 7]]
    private let themes = ["播种与生长", "灯火与节庆", "土地与收成", "金石与手作", "河流与雨水"]

    private var lunarDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = Calendar(identifier: .chinese)
        formatter.dateFormat = "U年 MMMMd日"
        return formatter.string(from: date)
    }

    private var lunarCycle: Int {
        Calendar(identifier: .chinese).component(.year, from: date) - 1
    }

    private var pairing: String {
        if harmony.contains([first, second].sorted()) { return "传统生肖六合" }
        if abs(first - second) == 6 { return "传统生肖六冲" }
        if first != second && first % 4 == second % 4 { return "同属传统生肖三合组" }
        return first == second ? "生肖相同" : "民俗合参：其他组合"
    }

    private func strokes(_ input: String) -> [Int] {
        let values = input.split(whereSeparator: \.isWhitespace)
        let numbers = values.compactMap { Int($0) }.filter { (1...60).contains($0) }
        return (1...2).contains(values.count) && numbers.count == values.count ? numbers : []
    }

    private var grids: [(String, Int)] {
        let family = strokes(surname)
        let name = strokes(given)
        guard let lastFamily = family.last, let firstName = name.first else { return [] }
        let familySum = family.reduce(0, +)
        let nameSum = name.reduce(0, +)
        let familyPadding = family.count == 1 ? 1 : 0
        let namePadding = name.count == 1 ? 1 : 0
        return [
            ("天格", familySum + familyPadding),
            ("人格", lastFamily + firstName),
            ("地格", nameSum + namePadding),
            ("外格", familySum - lastFamily + nameSum - firstName + familyPadding + namePadding),
            ("总格", familySum + nameSum)
        ]
    }

    var body: some View {
        Form {
            Section("农历与流年趣味") {
                DatePicker("公历日期", selection: $date, displayedComponents: .date)
                    .environment(\.calendar, Calendar(identifier: .gregorian))
                LabeledContent("农历（春节换年）", value: lunarDate)
                LabeledContent("生肖", value: String(animals[lunarCycle % 12]))
                Text("这一干支年的民俗主题：\(themes[lunarCycle % 10 / 2])。")
                Text("仅供民俗娱乐").font(.caption).foregroundStyle(.secondary)
            }
            Section("姓名五格") {
                TextField("姓的康熙笔画，按字用空格分隔", text: $surname)
                    .keyboardType(.numbersAndPunctuation)
                TextField("名的康熙笔画，按字用空格分隔", text: $given)
                    .keyboardType(.numbersAndPunctuation)
                ForEach(grids, id: \.0) { item in
                    LabeledContent(item.0, value: String(item.1))
                }
                Text("姓和名各支持一至两个字，每字 1–60 画。仅供取名文化参考。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("生肖趣味合参") {
                Picker("甲方生肖", selection: $first) {
                    ForEach(animals.indices, id: \.self) { Text(String(animals[$0])).tag($0) }
                }
                Picker("乙方生肖", selection: $second) {
                    ForEach(animals.indices, id: \.self) { Text(String(animals[$0])).tag($0) }
                }
                Text(pairing)
                Text("仅供民俗游戏，不能作为婚恋依据。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
