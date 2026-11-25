import SwiftUI

struct FolkCultureView: View {
    let title: String
    @State private var name = ""
    @State private var male: Bool?
    @State private var lunar = false
    @State private var leap = false
    @State private var year = ""
    @State private var month = ""
    @State private var day = ""
    @State private var hour: Int?
    @State private var queryYear = ""
    @State private var topics = Set(CeceCalendar.topics)
    @State private var report: [String] = []
    @State private var error = ""

    var body: some View {
        Form {
            Section("八字解析") {
                TextField("姓名（选填）", text: $name)
                Picker("性别", selection: $male) {
                    Text("请选择").tag(nil as Bool?)
                    Text("男").tag(Optional(true))
                    Text("女").tag(Optional(false))
                }
                Picker("历法", selection: $lunar) {
                    Text("公历").tag(false)
                    Text("农历").tag(true)
                }
                TextField("出生年（1901–2099）", text: $year).keyboardType(.numberPad)
                TextField("月", text: $month).keyboardType(.numberPad)
                TextField("日", text: $day).keyboardType(.numberPad)
                if lunar { Toggle("确认使用农历闰月", isOn: $leap) }
                Picker("出生时辰", selection: $hour) {
                    Text("请选择").tag(nil as Int?)
                    ForEach(CeceCalendar.branches.indices, id: \.self) { index in
                        Text(CeceCalendar.period(index)).tag(Optional(index))
                    }
                }
                Text("按北京时间和时辰中点排盘，子时取 00:00。").font(.footnote).foregroundStyle(.secondary)
                TextField("流年查询年份（默认今年）", text: $queryYear).keyboardType(.numberPad)
                ForEach(CeceCalendar.topics, id: \.self) { topic in
                    Toggle(topic, isOn: Binding(get: { topics.contains(topic) }, set: { selected in
                        if selected { topics.insert(topic) } else { topics.remove(topic) }
                    }))
                }
                Button("生成八字与大运报告", action: calculate)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            if !report.isEmpty {
                Section(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "八字报告" : "\(name)的八字报告") {
                    ForEach(report.indices, id: \.self) { Text(report[$0]) }
                    Text("仅供娱乐参考，不作为人生决策依据。").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func calculate() {
        report = []
        guard let male, let hour, let year = Int(year), let month = Int(month), let day = Int(day) else {
            error = "请补全性别、出生年月日和时辰。"
            return
        }
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        guard let selectedYear = queryYear.isEmpty ? currentYear : Int(queryYear),
              (1901...min(2099, currentYear + 10)).contains(selectedYear) else {
            error = "请输入有效的流年年份，最远可查到当前年份后十年。"
            return
        }
        do {
            report = try CeceCalendar.report(year: year, month: month, day: day, hour: hour,
                                             lunar: lunar, leap: leap, male: male, queryYear: selectedYear, topics: topics)
            error = ""
        } catch let failure {
            error = failure.localizedDescription
        }
    }
}

private enum CeceCalendar {
    static let topics = ["事业", "财运", "感情", "健康"]
    static let stems = Array("甲乙丙丁戊己庚辛壬癸")
    static let branches = Array("子丑寅卯辰巳午未申酉戌亥")
    static let elements = Array("木火土金水")
    static let branchElements = [4, 2, 0, 0, 2, 1, 1, 2, 3, 3, 2, 4]

    struct Month: Decodable {
        let number: Int
        let days: Int
        let start: String
        init(from decoder: Decoder) throws {
            var row = try decoder.unkeyedContainer()
            number = try row.decode(Int.self)
            days = try row.decode(Int.self)
            start = try row.decode(String.self)
        }
    }

    struct Almanac: Decodable {
        let terms: [String: [String]]
        let months: [String: [Month]]
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static let almanac: Almanac? = {
        guard let url = Bundle.main.url(forResource: "CeceCalendar", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Almanac.self, from: data)
    }()

    static func period(_ index: Int) -> String {
        let range = index == 0 ? "23:00–01:00" : String(format: "%02d:00–%02d:00", index * 2 - 1, index * 2 + 1)
        return "\(branches[index])时（\(range)）"
    }

    static func report(year: Int, month: Int, day: Int, hour: Int, lunar: Bool, leap: Bool, male: Bool, queryYear: Int, topics: Set<String> = Set(CeceCalendar.topics)) throws -> [String] {
        guard (1901...2099).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            throw Failure("请输入范围内有效的出生日期。")
        }
        guard let almanac else { throw Failure("排盘资料暂不可用。") }
        var civil = Calendar(identifier: .gregorian)
        civil.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = civil
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = civil.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let input = String(format: "%04d-%02d-%02d", year, month, day)
        let date: Date
        if lunar {
            guard let chosen = almanac.months[String(year)]?.first(where: { $0.number == (leap ? -month : month) }),
                  day <= chosen.days, let start = formatter.date(from: chosen.start),
                  let converted = civil.date(byAdding: .day, value: day - 1, to: start) else {
                throw Failure("该农历日期不存在，请核对月份、闰月和日。")
            }
            date = converted
        } else {
            guard let parsed = formatter.date(from: input), formatter.string(from: parsed) == input else {
                throw Failure("该公历日期不存在。")
            }
            date = parsed
        }
        let civilYear = civil.component(.year, from: date)
        let dateText = formatter.string(from: date)
        let timestamp = dateText + String(format: " %02d:00:00", hour * 2)
        guard let terms = almanac.terms[String(civilYear)], terms.count == 12,
              let anchor = formatter.date(from: "2000-01-01"),
              let elapsed = civil.dateComponents([.day], from: anchor, to: date).day else {
            throw Failure("该日期超出排盘范围。")
        }
        let boundary = terms.lastIndex(where: { $0 <= timestamp }) ?? -1
        let yearIndex = mod(civilYear - 1984 - (boundary < 1 ? 1 : 0), 60)
        let monthOffset = mod(boundary - 1, 12)
        let monthStem = ((yearIndex % 5) * 2 + 2 + monthOffset) % 10
        let dayIndex = mod(elapsed + 54, 60)
        let pillars = [(yearIndex % 10, yearIndex % 12), (monthStem, (monthOffset + 2) % 12),
                       (dayIndex % 10, dayIndex % 12), (((dayIndex % 5) * 2 + hour) % 10, hour)]
        var counts = Array(repeating: 0, count: 5)
        for (stem, branch) in pillars { counts[stem / 2] += 1; counts[branchElements[branch]] += 1 }
        let summary = counts.indices.map { "\(elements[$0]) \(counts[$0])" }.joined(separator: "　")
        let dayElement = (dayIndex % 10) / 2
        let support = counts[dayElement] - 1 + counts[mod(dayElement - 1, 5)]
        let strength = support >= 4 ? "表层生扶较多" : support <= 2 ? "表层生扶较少" : "表层生扶居中"
        var result = [
            "公历 \(dateText) · \(period(hour))",
            zip(["年柱", "月柱", "日柱", "时柱"], pillars).map {
                "\($0.0) \(stems[$0.1.0])\(branches[$0.1.1])"
            }.joined(separator: "　"),
            "五行分布（表层干支）\n\(summary)",
            "日主 \(stems[dayIndex % 10])\(elements[dayElement]) · \(strength)（简化统计）",
        ]
        let career = ["安排持续学习的时间", "练习把想法讲清楚", "把长期目标拆成小步骤", "为重要工作订立验收标准", "为变动留出调整空间"]
        result.append("事业 · 可从日主的五行意象联想到：\(career[dayElement])。")
        result.append("婚姻 · 把日支\(branches[dayIndex % 12])当作交流话题，聊聊双方如何表达需求和分担责任。")
        result.append("健康 · 以规律作息、适量活动和休息为日常观察主题。")
        result.append("子女 · 可把时支\(branches[hour])作为亲子交流主题，留意彼此喜欢的陪伴方式。")
        let forward = male == (yearIndex % 2 == 0)
        let adjacent = forward
            ? (boundary < 11 ? terms[boundary + 1] : almanac.terms[String(civilYear + 1)]?.first)
            : (boundary >= 0 ? terms[boundary] : almanac.terms[String(civilYear - 1)]?.last)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let adjacent, let term = formatter.date(from: adjacent), let birth = formatter.date(from: timestamp) else {
            return result
        }
        let minutes = abs(Int(floor(term.timeIntervalSince1970 / 60)) - Int(floor(birth.timeIntervalSince1970 / 60)))
        let startAge = DateComponents(year: minutes / 4320, month: minutes % 4320 / 360,
                                      day: minutes % 360 / 12, hour: minutes % 12 * 2)
        guard let start = civil.date(byAdding: startAge, to: birth) else { return result }
        let startYear = civil.component(.year, from: start)
        let annual = mod(queryYear - 1984, 60)
        result.append("流年 \(queryYear) \(stems[annual % 10])\(branches[annual % 12])（立春起）")
        formatter.dateFormat = "yyyy-MM-dd"
        result.append("大运\(forward ? "顺排" : "逆排") · 起运 \(formatter.string(from: start))")
        let index = max(0, (queryYear - startYear) / 10)
        for step in index..<(index + 4) {
            let delta = (step + 1) * (forward ? 1 : -1)
            let stem = stems[mod(monthStem + delta, 10)]
            let branch = branches[mod(monthOffset + 2 + delta, 12)]
            result.append("\(startYear + step * 10)–\(startYear + step * 10 + 9)  \(stem)\(branch)")
        }
        let flowElement = (annual % 10) / 2
        let flowRelation = ["同类", "日主相生", "日主相克", "受流年相克", "受流年相生"][mod(flowElement - dayElement, 5)]
        result.append("流年天干属\(elements[flowElement]) · 与日主属于\(flowRelation)的传统关系。")
        let tips = [career[flowElement] + "。", "整理收支和近期计划。", "安排一次讨论彼此近况的时间。", "留意作息、运动与休息是否均衡。"]
        for (topic, tip) in zip(Self.topics, tips) where topics.contains(topic) {
            result.append("流年\(topic) · \(tip)")
        }
        if queryYear < startYear { result.append("所查年份早于起运。") }
        else if (queryYear - startYear) % 10 == 0 { result.append("所查年份为起运或换运年份，大运区间按公历年展示。") }
        return result
    }

    private static func mod(_ value: Int, _ by: Int) -> Int { (value % by + by) % by }
}
