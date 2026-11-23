import CryptoKit
import MapKit
import PhotosUI
import Vision
import SceneKit
import SwiftUI

private struct NookRoom: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var length = 5.0
    var width = 4.0
    var height = 2.8
    var note = ""
    var address = ""
    var latitude: Double?
    var longitude: Double?
    var finish = NookFinish()
    var schemes: [NookFinish] = []
    var items: [NookItem] = []
}

private struct NookFinish: Codable, Identifiable {
    var id = UUID()
    var wall = "暖白"
    var floor = "木地板"
    var light = "日间"
}

private enum NookMaterial: String, CaseIterable, Identifiable {
    case cabinet = "木质收纳柜", sofa = "布艺沙发", table = "木桌", bed = "软包床", appliance = "家电", photo = "我的物品照片"
    var id: String { rawValue }
}

private struct NookItem: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var category = "家具"
    var length = 100.0
    var width = 60.0
    var height = 80.0
    var x = 0.0
    var z = 0.0
    var rotation = 0.0
    var scale = 1.0
    var value = 0.0
    var preview = false
    var idle = false
    var photo: Data?
    var material: String?

    var appearance: NookMaterial {
        if let material, let choice = NookMaterial(rawValue: material), choice != .photo || photo != nil { return choice }
        if name.contains("沙发") { return .sofa }
        if name.contains("床") { return .bed }
        if name.contains("桌") { return .table }
        return category == "家电" ? .appliance : .cabinet
    }

    func overlaps(_ other: NookItem) -> Bool {
        func axes(_ item: NookItem) -> [SIMD2<Double>] {
            let angle = item.rotation * .pi / 180
            return [SIMD2(cos(angle), sin(angle)), SIMD2(-sin(angle), cos(angle))]
        }
        func dot(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.x + a.y * b.y }
        let a = axes(self), b = axes(other)
        let delta = SIMD2(other.x - x, other.z - z)
        return (a + b).allSatisfy { axis in
            let own = (abs(dot(axis, a[0])) * length + abs(dot(axis, a[1])) * width) * scale / 200
            let theirs = (abs(dot(axis, b[0])) * other.length + abs(dot(axis, b[1])) * other.width) * other.scale / 200
            return abs(dot(delta, axis)) < own + theirs - 0.001
        }
    }

    var footprint: (Double, Double) {
        let angle = rotation * .pi / 180
        let c = abs(cos(angle)), s = abs(sin(angle))
        return ((length*c + width*s)*scale/200, (length*s + width*c)*scale/200)
    }
}

struct NookView: View {
    let account: String
    let title: String
    @State private var rooms: [NookRoom] = []
    @State private var path: [UUID] = []
    @State private var draft: NookRoom?
    @State private var error: String?
    @State private var readFailed = false

    private var archive: URL {
        let name = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL.applicationSupportDirectory.appending(path: "Nook", directoryHint: .isDirectory).appending(path: name + ".json")
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if rooms.isEmpty {
                    ContentUnavailableView("还没有房间", systemImage: "house", description: Text("填写实际长宽高，创建可摆放物品的 3D 房间。"))
                }
                ForEach(rooms) { room in
                    NavigationLink(value: room.id) {
                        LabeledContent(room.name, value: "\(room.items.filter { !$0.preview }.count) 件物品")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(Text(verbatim: title))
            .toolbar {
                Button("新建房间", systemImage: "plus") { draft = NookRoom() }
                    .disabled(readFailed)
            }
            .navigationDestination(for: UUID.self) { id in
                if let index = rooms.firstIndex(where: { $0.id == id }) {
                    NookRoomView(room: rooms[index], save: { store($0) })
                }
            }
            .sheet(item: $draft) { room in
                NookRoomForm(room: room) { updated in
                    if store(updated) { path.append(updated.id); return true }
                    return false
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: archive.path) else { return }
        do { rooms = try JSONDecoder().decode([NookRoom].self, from: Data(contentsOf: archive)) }
        catch { readFailed = true; self.error = "房间档案读取失败，已保留原文件。" }
    }

    private func store(_ room: NookRoom) -> Bool {
        guard !readFailed else { return false }
        var updated = rooms
        if let index = updated.firstIndex(where: { $0.id == room.id }) { updated[index] = room }
        else { updated.append(room) }
        do {
            try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: archive, options: [.atomic, .completeFileProtection])
            rooms = updated
            return true
        } catch {
            self.error = "房间未能保存，请重试。"
            return false
        }
    }
}

private struct NookRoomForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var room: NookRoom
    let save: (NookRoom) -> Bool
    @State private var search = ""
    @State private var locations: [MKMapItem] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("房间") {
                    TextField("房间名称", text: $room.name)
                    number("长（米）", $room.length)
                    number("宽（米）", $room.width)
                    number("高（米）", $room.height)
                    TextField("备注", text: $room.note, axis: .vertical)
                }
                Section("地址") {
                    TextField("搜索地址", text: $search)
                    Button(searching ? "搜索中…" : "搜索地图") { Task { await find() } }
                        .disabled(searching || search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(Array(locations.enumerated()), id: \.offset) { _, place in
                        Button(place.placemark.title ?? place.name ?? "地图地点") {
                            room.address = place.placemark.title ?? place.name ?? ""
                            room.latitude = place.placemark.coordinate.latitude
                            room.longitude = place.placemark.coordinate.longitude
                            locations = []
                        }
                    }
                    if !room.address.isEmpty { Text(room.address) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("房间档案")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        room.name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if save(room) { dismiss() } else { error = "保存失败，请重试。" }
                    }.disabled(room.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                               ![room.length, room.width, room.height].allSatisfy { (0.5...100).contains($0) })
                }
            }
        }
    }

    @MainActor private func find() async {
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = search
        do {
            locations = Array((try await MKLocalSearch(request: request).start()).mapItems.prefix(8))
            error = locations.isEmpty ? "未找到匹配地址。" : nil
        } catch {
            locations = []
            self.error = "地址搜索失败，请检查网络后重试。"
        }
    }
}

private func number(_ label: String, _ value: Binding<Double>) -> some View {
    LabeledContent(label) {
        TextField(label, value: value, format: .number)
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
    }
}

private struct NookRoomView: View {
    @State var room: NookRoom
    let save: (NookRoom) -> Bool
    @State private var selected: UUID?
    @State private var itemDraft: NookItem?
    @State private var enlarged: NookItem?
    @State private var editRoom = false
    @State private var decorate = false
    @State private var overhead = false
    @State private var filter = ""
    @State private var saveError = false
    @State private var placementError: String?
    @State private var orientationError = false

    private var assets: [NookItem] { room.items.filter { !$0.preview } }
    private var visibleItems: [NookItem] {
        room.items.filter { filter.isEmpty || $0.name.localizedStandardContains(filter) || $0.category.localizedStandardContains(filter) }
    }

    private func roomCanvas(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NookScene(room: room, selected: selected, overhead: overhead) { id, x, z in
                guard let index = room.items.firstIndex(where: { $0.id == id }) else { return false }
                var next = room
                next.items[index].x = x
                next.items[index].z = z
                if let reason = blocked(next.items[index], in: next) {
                    placementError = reason
                    return false
                }
                placementError = nil
                guard persist(next) else { saveError = true; return false }
                return true
            } select: { id in
                selected = id
                if !overhead { enlarged = room.items.first { $0.id == id } }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            Toggle("俯视摆放", isOn: $overhead)
            Text(overhead ? "直接拖动物品；也可先选物品，再点空位。" : "拖动物品可搬动。拖空白处旋转视角，双指缩放。")
                .font(.caption).foregroundStyle(.secondary)
            if let placementError {
                Text(placementError).font(.caption).foregroundStyle(.orange)
            }
            if let item = room.items.first(where: { $0.id == selected }) {
                HStack {
                    Button("放大", systemImage: "arrow.up.left.and.arrow.down.right") { enlarged = item }
                    Spacer()
                    Button("编辑物品", systemImage: "slider.horizontal.3") { itemDraft = item }
                }.font(.footnote)
            }
        }.padding(.horizontal, 12)
    }

    private var assetSection: some View {
        Section("资产与预览") {
            LabeledContent("自有资产", value: "\(assets.count) 件")
            LabeledContent("参考总值", value: assets.reduce(0) { $0 + $1.value }.formatted(.currency(code: "CNY")))
            TextField("搜索名称或类别", text: $filter)
            ForEach(visibleItems) { item in
                Button {
                    selected = item.id
                    enlarged = item
                } label: {
                    HStack {
                        Label(item.name, systemImage: selected == item.id ? "checkmark.circle.fill" : "cube")
                        Spacer()
                        Text(item.preview ? "意向预览" : item.category).foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button("编辑") { itemDraft = item }
                    Button("移除", role: .destructive) {
                        update { $0.items.removeAll { $0.id == item.id } }
                        if selected == item.id { selected = nil }
                    }
                }
            }
            Button("录入自有物品", systemImage: "plus") { itemDraft = NookItem() }
            Button("添加意向预览", systemImage: "cube.transparent") { itemDraft = NookItem(preview: true) }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                HStack(alignment: .top, spacing: 0) {
                    roomCanvas(height: max(115, geometry.size.height - 103))
                        .frame(width: geometry.size.width * 0.58)
                    Divider()
                    List { assetSection }
                }
            } else {
                VStack(spacing: 6) {
                    roomCanvas(height: max(160, min(360, geometry.size.height * 0.54)))
                    List { assetSection }
                }
            }
        }
        .navigationTitle(Text(verbatim: room.name))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NookOrientationMenu { orientationError = true }.frame(width: 34, height: 34)
            }
            Menu("房间操作", systemImage: "ellipsis.circle") {
                Button("编辑房间", systemImage: "pencil") { editRoom = true }
                Button("虚拟装修", systemImage: "paintpalette") { decorate = true }
            }
        }
        .fullScreenCover(item: $enlarged) { item in
            NookItemPreview(item: item)
        }
        .sheet(isPresented: $editRoom) { NookRoomForm(room: room, save: persist) }
        .sheet(isPresented: $decorate) {
            NookDecorationView(room: room, save: persist)
        }
        .sheet(item: $itemDraft) { item in
            NookItemForm(item: item) { item in
                var next = room
                if let index = next.items.firstIndex(where: { $0.id == item.id }) { next.items[index] = item }
                else { next.items.append(item) }
                guard persist(next) else { return false }
                selected = item.id
                return true
            }
        }
        .alert("当前窗口无法切换方向", isPresented: $orientationError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请检查设备方向锁定。iPad 分屏时可调整窗口宽度。")
        }
        .alert("保存未完成", isPresented: $saveError) { Button("好", role: .cancel) {} }
    }

    private func persist(_ next: NookRoom) -> Bool {
        guard save(next) else { return false }
        room = next
        return true
    }
    private func update(_ action: (inout NookRoom) -> Void) {
        var next = room
        action(&next)
        if !persist(next) { saveError = true }
    }

    private func blocked(_ item: NookItem, in room: NookRoom) -> String? {
        let (x, z) = item.footprint
        if abs(item.x) + x > room.length / 2 + 0.001 ||
            abs(item.z) + z > room.width / 2 + 0.001 ||
            item.height * item.scale / 100 > room.height {
            return "放不下：超出房间边界。"
        }
        if room.items.contains(where: { $0.id != item.id && item.overlaps($0) }) {
            return "这个位置已有物品，请拖到空位。"
        }
        return nil
    }

    private func warning(_ item: NookItem) -> String? {
        if let reason = blocked(item, in: room) { return reason }
        let (x, z) = item.footprint
        let clearance = min(room.length / 2 - abs(item.x) - x, room.width / 2 - abs(item.z) - z)
        return clearance < 0.6 ? "距最近墙面不足 60 厘米。" : nil
    }
}

private struct NookItemForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: NookItem
    let save: (NookItem) -> Bool
    @State private var error = false
    @State private var camera = false
    @State private var photo: PhotosPickerItem?
    @State private var recognitionStatus: String?
    @State private var recognizing = false

    @MainActor private func recognize(_ load: () async throws -> Data?) async {
        guard !recognizing else { return }
        recognizing = true
        defer { recognizing = false }
        do {
            guard let data = try await load(), let image = UIImage(data: data) else {
                recognitionStatus = "无法读取照片。"
                return
            }
            let ratio = min(1, 720 / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let thumb = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let jpeg = thumb.jpegData(compressionQuality: 0.72) else { throw CocoaError(.fileWriteUnknown) }
            item.photo = jpeg
            if let candidate = try await NookPhotoRecognition.suggest(jpeg) {
                if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { item.name = candidate.name; item.category = candidate.category }
                recognitionStatus = "识别建议：\(candidate.name) · \(candidate.category)。请核对后保存。"
            } else {
                recognitionStatus = "未能可靠识别这件物品，可填写名称和分类。"
            }
        } catch {
            recognitionStatus = "照片读取或识别失败，可手动填写。"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !item.preview {
                    Section("照片识别") {
                        if let data = item.photo, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("拍照识别", systemImage: "camera") { camera = true }.disabled(recognizing)
                        }
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("选照片识别", systemImage: "photo")
                        }.disabled(recognizing)
                        if recognizing { ProgressView("正在设备上识别…") }
                        if let recognitionStatus { Text(recognitionStatus).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                TextField("物品名称", text: $item.name)
                Picker("分类", selection: $item.category) {
                    ForEach(["家具","家电","收纳","厨具","服饰","其他"], id: \.self) { Text($0).tag($0) }
                }
                Picker("房间内的展示", selection: Binding(get: { item.appearance }, set: { item.material = $0.rawValue })) {
                    ForEach(NookMaterial.allCases.filter { $0 != .photo || item.photo != nil }) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                number("长（厘米）", $item.length)
                number("宽（厘米）", $item.width)
                number("高（厘米）", $item.height)
                Stepper("旋转 \(Int(item.rotation))°", value: $item.rotation, in: 0...360, step: 15)
                Stepper("比例 \(item.scale.formatted(.percent))", value: $item.scale, in: 0.25...3, step: 0.25)
                if !item.preview {
                    number("参考价值（元）", $item.value)
                    Toggle("标记闲置", isOn: $item.idle)
                    if item.idle {
                        ShareLink(item: "\(item.name)\n分类：\(item.category)\n尺寸：\(item.length.formatted()) × \(item.width.formatted()) × \(item.height.formatted()) 厘米\n参考价：\(item.value.formatted(.currency(code: "CNY")))") {
                            Label("分享闲置资料", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                if error { Text("保存失败，请重试。").foregroundStyle(.red) }
            }
            .task(id: photo) {
                guard let photo else { return }
                await recognize { try await photo.loadTransferable(type: Data.self) }
            }
            .fullScreenCover(isPresented: $camera) {
                DearCamera(mode: .photo) { result in
                    camera = false
                    switch result {
                    case .success(let capture):
                        guard let url = capture?.0 else { return }
                        Task {
                            defer { try? FileManager.default.removeItem(at: url) }
                            await recognize { try Data(contentsOf: url) }
                        }
                    case .failure:
                        recognitionStatus = "拍摄未完成，请检查相机权限后重试。"
                    }
                }.ignoresSafeArea()
            }
            .navigationTitle(item.preview ? "意向商品" : "自有物品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if save(item) { dismiss() } else { error = true }
                    }.disabled(recognizing || item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                ![item.length,item.width,item.height].allSatisfy { (1...10000).contains($0) } || !(0...100000000).contains(item.value))
                }
            }
        }
    }
}

private enum NookPhotoRecognition {
    struct Candidate: Sendable {
        let name: String
        let category: String
    }

    nonisolated static func suggest(_ bytes: Data) async throws -> Candidate? {
        try await Task.detached(priority: .userInitiated) { () throws -> Candidate? in
            let request = VNClassifyImageRequest()
            try VNImageRequestHandler(data: bytes).perform([request])
            let matches: [(String, String, String)] = [
                ("sofa", "沙发", "家具"), ("couch", "沙发", "家具"),
                ("chair", "椅子", "家具"), ("table", "桌子", "家具"),
                ("desk", "书桌", "家具"), ("bed", "床", "家具"),
                ("refrigerator", "冰箱", "家电"), ("microwave", "微波炉", "家电"),
                ("television", "电视", "家电"), ("vacuum", "吸尘器", "家电"),
                ("shelf", "置物架", "收纳"), ("cabinet", "柜子", "收纳"),
                ("luggage", "行李箱", "收纳"), ("kettle", "水壶", "厨具"),
                ("pan", "锅具", "厨具"), ("cup", "杯子", "厨具"),
                ("shoe", "鞋", "服饰"), ("jacket", "夹克", "服饰"),
                ("book", "书籍", "其他"), ("plant", "植物", "其他")
            ]
            for observation in (request.results ?? []).prefix(8) where observation.confidence >= 0.35 {
                let words = Set(observation.identifier.lowercased().split { !$0.isLetter }.map(String.init))
                if let match = matches.first(where: { words.contains($0.0) }) {
                    return Candidate(name: match.1, category: match.2)
                }
            }
            return nil
        }.value
    }
}

private struct NookItemPreview: View {
    @Environment(\.dismiss) private var dismiss
    let item: NookItem

    private var stage: NookRoom {
        var copy = item
        copy.x = 0
        copy.z = 0
        let extent = max(copy.length, copy.width, copy.height) * copy.scale / 100
        return NookRoom(name: item.name, length: extent * 1.5, width: extent * 1.5, height: extent, items: [copy])
    }

    var body: some View {
        NavigationStack {
            VStack {
                NookScene(room: stage, selected: nil, overhead: false, move: { _, _, _ in false }, select: { _ in }, isolated: true)
                    .accessibilityLabel("物品 3D 预览")
                Text("\(item.length.formatted()) × \(item.width.formatted()) × \(item.height.formatted()) 厘米")
                    .font(.footnote).padding(.bottom, 8)
            }
            .navigationTitle(Text(verbatim: item.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct NookDecorationView: View {
    @Environment(\.dismiss) private var dismiss
    @State var room: NookRoom
    let save: (NookRoom) -> Bool
    @State private var error = false
    var body: some View {
        NavigationStack {
            Form {
                NookScene(room: room, selected: nil, overhead: false, move: { _, _, _ in false }, select: { _ in }).frame(height: 240)
                Picker("墙面", selection: $room.finish.wall) { ForEach(["暖白","灰绿","浅蓝"], id: \.self) { Text($0).tag($0) } }
                Picker("地面", selection: $room.finish.floor) { ForEach(["木地板","瓷砖"], id: \.self) { Text($0).tag($0) } }
                Picker("灯光", selection: $room.finish.light) { ForEach(["日间","暖色"], id: \.self) { Text($0).tag($0) } }
                ForEach(Array(room.schemes.enumerated()), id: \.element.id) { index, scheme in
                    Button("方案 \(index + 1)：\(scheme.wall) · \(scheme.floor) · \(scheme.light)") { room.finish = scheme }
                }
                Button("另存方案") {
                    var scheme = room.finish
                    scheme.id = UUID()
                    room.schemes.append(scheme)
                }
                if error { Text("保存失败，请重试。").foregroundStyle(.red) }
            }.navigationTitle("虚拟装修")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if save(room) { dismiss() } else { error = true } } }
                }
        }
    }
}

private struct NookOrientationMenu: UIViewRepresentable {
    let failed: @MainActor () -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "iphone.landscape"), for: .normal)
        button.accessibilityLabel = "切换横竖屏"
        button.showsMenuAsPrimaryAction = true
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        func action(_ title: String, orientation: UIInterfaceOrientationMask) -> UIAction {
            UIAction(title: title) { [weak button] _ in
                guard let window = button?.window, let scene = window.windowScene else { failed(); return }
                var controller = window.rootViewController
                while let presented = controller?.presentedViewController { controller = presented }
                controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in
                    Task { @MainActor in failed() }
                }
            }
        }
        button.menu = UIMenu(title: "房间显示方向", children: [
            action("横屏", orientation: .landscape),
            action("竖屏", orientation: .portrait)
        ])
    }
}

private struct NookScene: UIViewRepresentable {
    let room: NookRoom
    let selected: UUID?
    let overhead: Bool
    let move: (UUID, Double, Double) -> Bool
    let select: (UUID?) -> Void
    var isolated = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let drag = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.drag(_:)))
        drag.maximumNumberOfTouches = 1
        drag.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoom(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(drag)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        view.allowsCameraControl = isolated && !overhead
        if coordinator.sceneKey == sceneKey { return }
        let previousCamera = coordinator.lastOverhead == overhead ? view.pointOfView : nil
        let zoom = previousCamera?.camera?.orthographicScale
        coordinator.lastOverhead = overhead
        coordinator.sceneKey = sceneKey
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.88, green: 0.92, blue: 0.82, alpha: 1)
        let wall: UIColor = room.finish.wall == "灰绿" ? UIColor(red: 0.76, green: 0.85, blue: 0.66, alpha: 1) :
            room.finish.wall == "浅蓝" ? UIColor(red: 0.72, green: 0.84, blue: 0.91, alpha: 1) : UIColor(red: 0.99, green: 0.89, blue: 0.73, alpha: 1)
        let wood = room.finish.floor == "木地板"
        let floor = box(scene, width: room.length, height: 0.10, depth: room.width, at: SCNVector3(0,-0.05,0),
                        color: wood ? UIColor(red: 0.73, green: 0.56, blue: 0.40, alpha: 1) : .systemGray4)
        if let material = floor.geometry?.firstMaterial {
            material.diffuse.contents = floorTexture(wood: wood)
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(max(1, room.length / 1.8)), 5, 1)
        }
        if !isolated { addDollhouseShell(to: scene, wall: wall) }
        for item in room.items { scene.rootNode.addChildNode(assetNode(item)) }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        let extent = max(room.length, room.width, room.height)
        camera.camera?.zFar = extent * 10
        if overhead {
            camera.position = SCNVector3(0, extent * 2, 0)
            camera.eulerAngles.x = -.pi/2
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = zoom ?? extent * 1.35
        } else {
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = zoom ?? max(room.height * 1.4, (room.length + room.width) * 0.62)
            camera.position = SCNVector3(extent * 1.32, extent * 1.92, extent * 1.32)
            camera.look(at: SCNVector3(0, room.height * 0.28, 0))
            if let previousCamera {
                camera.position = previousCamera.position
                camera.orientation = previousCamera.orientation
            }
        }
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 530
        ambient.light?.color = room.finish.light == "暖色" ? UIColor(red: 1, green: 0.81, blue: 0.62, alpha: 1) : UIColor.white
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 930
        key.light?.castsShadow = true
        key.light?.shadowRadius = 4
        key.light?.shadowSampleCount = 8
        key.light?.shadowColor = UIColor(red: 0.28, green: 0.20, blue: 0.14, alpha: 0.22)
        key.eulerAngles = SCNVector3(-0.9, -0.55, 0)
        scene.rootNode.addChildNode(key)
        view.scene = scene
        view.pointOfView = camera
    }

    private func addDollhouseShell(to scene: SCNScene, wall: UIColor) {
        let trim = UIColor(red: 1, green: 0.95, blue: 0.84, alpha: 1)
        let edge = UIColor(red: 0.67, green: 0.44, blue: 0.29, alpha: 1)
        let left = -room.length / 2
        let back = -room.width / 2
        let border = min(0.13, min(room.length, room.width) * 0.07)
        let depth = border * 1.55
        let rail = min(0.09, room.height * 0.055)

        // A cutaway shell leaves the working floor and all existing placements untouched.
        box(scene, width: room.length + border * 2, height: depth, depth: room.width + border * 2,
            at: SCNVector3(0, -0.10-depth/2, 0), color: edge)
        box(scene, width: border, height: room.height, depth: room.width + border,
            at: SCNVector3(left-border/2, room.height/2, -border/2), color: wall)
        box(scene, width: room.length + border, height: room.height, depth: border,
            at: SCNVector3(-border/2, room.height/2, back-border/2), color: wall)
        for fraction in [0.025, 0.36, 0.975] {
            let y = room.height * fraction
            box(scene, width: border * 1.2, height: rail, depth: room.width + border,
                at: SCNVector3(left-border/2, y, -border/2), color: trim)
            box(scene, width: room.length + border, height: rail, depth: border * 1.2,
                at: SCNVector3(-border/2, y, back-border/2), color: trim)
        }
        if !overhead {
            let width = min(room.length * 0.48, 2.5)
            let depth = min(room.width * 0.42, 1.6)
            box(scene, width: width, height: 0.008, depth: depth,
                at: SCNVector3(room.length * 0.12, 0.004, room.width * 0.20),
                color: UIColor(red: 0.91, green: 0.66, blue: 0.64, alpha: 1))
            box(scene, width: width * 0.87, height: 0.010, depth: depth * 0.78,
                at: SCNVector3(room.length * 0.12, 0.005, room.width * 0.20),
                color: UIColor(red: 0.97, green: 0.81, blue: 0.69, alpha: 1))
            addWallPanels(to: scene, back: back, border: border, trim: trim)
        }
    }

    private func addWallPanels(to scene: SCNScene, back: Double, border: Double, trim: UIColor) {
        let panelWidth = min(room.length * 0.24, 1.05)
        let panelHeight = room.height * 0.31
        let position = room.length * 0.18
        let y = room.height * 0.69
        let glass = UIColor(red: 0.67, green: 0.85, blue: 0.86, alpha: 1)
        let seam = min(0.035, panelWidth * 0.08)
        box(scene, width: panelWidth, height: panelHeight, depth: border * 0.30,
            at: SCNVector3(position, y, back + border * 0.12), color: trim)
        for x in [-1.0, 1.0] {
            for level in [-1.0, 1.0] {
                box(scene, width: panelWidth / 2 - seam * 2, height: panelHeight / 2 - seam * 2, depth: seam,
                    at: SCNVector3(position + x * panelWidth / 4, y + level * panelHeight / 4, back + border * 0.29), color: glass)
            }
        }
        let artX = -room.length * 0.20
        box(scene, width: panelWidth * 0.65, height: panelHeight * 0.76, depth: border * 0.30,
            at: SCNVector3(artX, y, back + border * 0.12), color: trim)
        box(scene, width: panelWidth * 0.51, height: panelHeight * 0.60, depth: seam,
            at: SCNVector3(artX, y, back + border * 0.29),
            color: UIColor(red: 0.86, green: 0.63, blue: 0.67, alpha: 1))
    }

    private var sceneKey: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var geometry = room
        for index in geometry.items.indices { if geometry.items[index].appearance != .photo { geometry.items[index].photo = nil } }
        return try? encoder.encode(SceneState(room: geometry, selected: selected, overhead: overhead))
    }
    private struct SceneState: Encodable { let room: NookRoom; let selected: UUID?; let overhead: Bool }

    @discardableResult private func box(_ scene: SCNScene, width: Double, height: Double, depth: Double,
                                      at position: SCNVector3, color: UIColor) -> SCNNode {
        let shape = SCNBox(width: width, height: height, length: depth, chamferRadius: 0)
        shape.firstMaterial?.diffuse.contents = color
        shape.firstMaterial?.lightingModel = .physicallyBased
        shape.firstMaterial?.roughness.contents = 0.82
        let node = SCNNode(geometry: shape)
        node.position = position
        scene.rootNode.addChildNode(node)
        return node
    }

    private func floorTexture(wood: Bool) -> UIImage {
        let size = CGSize(width: 192, height: 192)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            for row in 0..<6 {
                let tone = CGFloat((row * 13) % 7) / 85
                cg.setFillColor((wood ? UIColor(red: 0.74 + tone, green: 0.57 + tone, blue: 0.43 + tone, alpha: 1) :
                                 UIColor(white: 0.83 + tone, alpha: 1)).cgColor)
                cg.fill(CGRect(x: 0, y: row * 32, width: 192, height: 32))
                cg.setFillColor(UIColor.black.withAlphaComponent(0.14).cgColor)
                cg.fill(CGRect(x: 0, y: row * 32, width: 192, height: 1))
                if wood {
                    cg.fill(CGRect(x: (row * 55) % 192, y: row * 32, width: 1, height: 32))
                    for strand in 0..<3 {
                        cg.setFillColor(UIColor.black.withAlphaComponent(0.035).cgColor)
                        cg.fill(CGRect(x: 0, y: row * 32 + 5 + strand * 8, width: 192, height: 1))
                    }
                } else {
                    cg.fill(CGRect(x: 96, y: row * 32, width: 1, height: 32))
                }
            }
        }
    }

    private func assetNode(_ item: NookItem) -> SCNNode {
        let root = SCNNode()
        root.name = item.id.uuidString
        root.position = SCNVector3(item.x, 0, item.z)
        root.eulerAngles.y = Float(-item.rotation * .pi / 180)
        root.scale = SCNVector3(item.length * item.scale / 100, item.height * item.scale / 100, item.width * item.scale / 100)
        root.opacity = item.preview ? 0.58 : 1
        let wood = UIColor(red: 0.74, green: 0.49, blue: 0.29, alpha: 1)
        let fabric = UIColor(red: 0.42, green: 0.68, blue: 0.61, alpha: 1)
        let pale = UIColor(red: 0.98, green: 0.91, blue: 0.79, alpha: 1)
        func part(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ y: Float, _ color: UIColor, x: Float = 0, z: Float = 0) {
            let shape = SCNBox(width: w, height: h, length: d, chamferRadius: min(0.055, min(w, min(h, d)) / 4))
            shape.firstMaterial?.diffuse.contents = color
            shape.firstMaterial?.lightingModel = .physicallyBased
            shape.firstMaterial?.roughness.contents = 0.78
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3(x, y, z)
            root.addChildNode(node)
        }
        switch item.appearance {
        case .sofa:
            part(1, 0.28, 0.92, 0.20, fabric)
            for x: Float in [-0.25, 0, 0.25] { part(0.24, 0.15, 0.68, 0.42, pale, x: x, z: 0.10) }
            part(0.19, 0.24, 0.14, 0.61, UIColor(red: 0.94, green: 0.68, blue: 0.46, alpha: 1), x: -0.27, z: -0.23)
            part(0.19, 0.24, 0.14, 0.61, UIColor(red: 0.90, green: 0.66, blue: 0.73, alpha: 1), x: 0.27, z: -0.23)
            part(1, 0.64, 0.16, 0.68, fabric, z: -0.41)
            for x: Float in [-0.43, 0.43] { part(0.14, 0.44, 0.85, 0.47, fabric, x: x) }
        case .table:
            part(1, 0.11, 1, 0.945, wood)
            for x: Float in [-0.39, 0.39] {
                for z: Float in [-0.39, 0.39] { part(0.10, 0.89, 0.10, 0.445, wood, x: x, z: z) }
            }
        case .bed:
            part(1, 0.25, 0.96, 0.19, wood)
            part(0.96, 0.24, 0.9, 0.43, pale, z: 0.035)
            part(0.96, 0.63, 0.10, 0.685, fabric, z: -0.44)
            part(0.78, 0.13, 0.20, 0.60, .white, z: -0.27)
            part(0.96, 0.09, 0.59, 0.57, fabric, z: 0.18)
        case .appliance:
            part(0.97, 0.97, 0.87, 0.5, UIColor(red: 0.70, green: 0.83, blue: 0.87, alpha: 1))
            part(0.94, 0.70, 0.09, 0.63, .systemGray3, z: 0.44)
            part(0.04, 0.26, 0.04, 0.59, .darkGray, x: -0.30, z: 0.48)
        case .cabinet:
            part(1, 0.94, 0.88, 0.53, wood)
            for y: Float in [0.23, 0.53, 0.83] {
                part(0.91, 0.27, 0.07, y, pale, z: 0.45)
                part(0.26, 0.035, 0.04, y + 0.035, wood, z: 0.49)
            }
        case .photo:
            if overhead { part(0.96, 0.025, 0.96, 0.05, pale) }
            else { part(0.96, 0.96, 0.09, 0.5, pale) }
            if let data = item.photo, let image = UIImage(data: data) {
                let plane = SCNPlane(width: 0.90, height: 0.90)
                let fit = CGSize(width: item.length * 2, height: (overhead ? item.width : item.height) * 2)
                let scale = min(720 / max(fit.width, fit.height), 1)
                let size = CGSize(width: max(1, fit.width * scale), height: max(1, fit.height * scale))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let texture = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    pale.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
                    let ratio = min(size.width / image.size.width, size.height / image.size.height)
                    let w = image.size.width * ratio, h = image.size.height * ratio
                    image.draw(in: CGRect(x: (size.width-w)/2, y: (size.height-h)/2, width: w, height: h))
                }
                plane.firstMaterial?.diffuse.contents = texture
                plane.firstMaterial?.lightingModel = .constant
                let picture = SCNNode(geometry: plane)
                if overhead {
                    picture.position = SCNVector3(0, 0.065, 0)
                    picture.eulerAngles.x = -.pi / 2
                } else {
                    picture.position = SCNVector3(0, 0.50, 0.049)
                }
                root.addChildNode(picture)
            }
        }
        if selected == item.id {
            part(1, 0.012, 1, 0.006, UIColor(red: 0.93, green: 0.62, blue: 0.25, alpha: 1))
        }
        return root
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: NookScene
        var sceneKey: Data?
        var lastOverhead = false
        private var moving: (node: SCNNode, id: UUID, original: SCNVector3, anchor: SCNVector3)?
        init(_ parent: NookScene) { self.parent = parent }

        private func asset(at point: CGPoint, in view: SCNView) -> (SCNNode, UUID)? {
            guard var node = view.hitTest(point, options: nil).first?.node else { return nil }
            while true {
                if let id = node.name.flatMap(UUID.init(uuidString:)) { return (node, id) }
                guard let next = node.parent else { return nil }
                node = next
            }
        }

        private func floorPoint(_ point: CGPoint, in view: SCNView) -> SCNVector3? {
            let near = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let far = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            let dy = far.y - near.y
            guard abs(dy) > 0.00001 else { return nil }
            let t = -near.y / dy
            let x = near.x + (far.x - near.x) * t
            let z = near.z + (far.z - near.z) * t
            guard t >= 0, x.isFinite, z.isFinite else { return nil }
            return SCNVector3(x, 0, z)
        }

        private var orbitAngle: Double?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard !parent.isolated, let view = gestureRecognizer.view as? SCNView else { return false }
            if gestureRecognizer is UIPinchGestureRecognizer { return moving == nil }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            if !parent.overhead { return true }
            let point = pan.location(in: view), delta = pan.translation(in: view)
            return asset(at: CGPoint(x: point.x - delta.x, y: point.y - delta.y), in: view) != nil
        }

        @objc func zoom(_ gesture: UIPinchGestureRecognizer) {
            guard let camera = (gesture.view as? SCNView)?.pointOfView?.camera else { return }
            camera.orthographicScale = min(160, max(0.5, camera.orthographicScale / gesture.scale))
            gesture.scale = 1
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView, moving == nil else { return }
            let point = gesture.location(in: view)
            if let (_, id) = asset(at: point, in: view) {
                parent.select(id)
            } else if parent.overhead, let id = parent.selected, let floor = floorPoint(point, in: view) {
                _ = parent.move(id, Double(floor.x), Double(floor.z))
            }
        }

        @objc func drag(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            if gesture.state == .began {
                let delta = gesture.translation(in: view)
                let start = CGPoint(x: point.x - delta.x, y: point.y - delta.y)
                if let (node, id) = asset(at: start, in: view), let anchor = floorPoint(start, in: view) {
                    moving = (node, id, node.position, anchor)
                } else if !parent.overhead, let camera = view.pointOfView {
                    orbitAngle = atan2(Double(camera.position.x), Double(camera.position.z))
                }
            }
            if let angle = orbitAngle, let camera = view.pointOfView {
                let next = angle - Double(gesture.translation(in: view).x) * 0.012
                let radius = hypot(Double(camera.position.x), Double(camera.position.z))
                camera.position.x = Float(sin(next) * radius)
                camera.position.z = Float(cos(next) * radius)
                camera.look(at: SCNVector3(0, parent.room.height * 0.28, 0))
                if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed { orbitAngle = nil }
                return
            }
            guard let drag = moving else { return }
            if gesture.state == .cancelled || gesture.state == .failed {
                drag.node.position = drag.original
                moving = nil
                return
            }
            guard let position = floorPoint(point, in: view) else {
                if gesture.state == .ended { drag.node.position = drag.original; moving = nil }
                return
            }
            let x = drag.original.x + position.x - drag.anchor.x
            let z = drag.original.z + position.z - drag.anchor.z
            drag.node.position = SCNVector3(x, 0, z)
            if gesture.state == .ended {
                moving = nil
                if !parent.move(drag.id, Double(x), Double(z)) { drag.node.position = drag.original }
                if parent.overhead { parent.select(drag.id) }
            }
        }
    }
}
