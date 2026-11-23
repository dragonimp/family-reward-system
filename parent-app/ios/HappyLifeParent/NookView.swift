import CryptoKit
import MapKit
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
    @State private var editRoom = false
    @State private var decorate = false
    @State private var overhead = false
    @State private var filter = ""
    @State private var saveError = false

    private var assets: [NookItem] { room.items.filter { !$0.preview } }
    private var visibleItems: [NookItem] {
        room.items.filter { filter.isEmpty || $0.name.localizedStandardContains(filter) || $0.category.localizedStandardContains(filter) }
    }

    var body: some View {
        List {
            Section {
                NookScene(room: room, selected: selected, overhead: overhead) { x, z in
                    guard let id = selected, let index = room.items.firstIndex(where: { $0.id == id }) else { return }
                    update { $0.items[index].x = x; $0.items[index].z = z }
                } select: { selected = $0 }
                .frame(height: 310)
                Toggle("俯视摆放", isOn: $overhead)
                Text(overhead ? "点选物品后拖动可摆放。双指可缩放。" : "拖动旋转视角，双指缩放。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let item = room.items.first(where: { $0.id == selected }) {
                    Button("编辑 \(item.name)", systemImage: "slider.horizontal.3") { itemDraft = item }
                    if let warning = warning(item) { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            Section("资产与预览") {
                LabeledContent("自有资产", value: "\(assets.count) 件")
                LabeledContent("参考总值", value: assets.reduce(0) { $0 + $1.value }.formatted(.currency(code: "CNY")))
                TextField("搜索名称或类别", text: $filter)
                ForEach(visibleItems) { item in
                    Button {
                        selected = item.id
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
        .navigationTitle(Text(verbatim: room.name))
        .toolbar {
            Menu("房间操作", systemImage: "ellipsis.circle") {
                Button("编辑房间", systemImage: "pencil") { editRoom = true }
                Button("虚拟装修", systemImage: "paintpalette") { decorate = true }
            }
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

    private func warning(_ item: NookItem) -> String? {
        let (x, z) = item.footprint
        let clearance = min(room.length/2 - abs(item.x) - x, room.width/2 - abs(item.z) - z)
        if clearance < 0 || item.height * item.scale / 100 > room.height { return "物品超出房间边界。" }
        if room.items.contains(where: { other in
            guard other.id != item.id else { return false }
            let (ox, oz) = other.footprint
            return abs(other.x-item.x) < x+ox && abs(other.z-item.z) < z+oz
        }) { return "与另一物品的占地范围重叠。" }
        if clearance < 0.6 { return "距最近墙面不足 60 厘米。" }
        return nil
    }
}

private struct NookItemForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: NookItem
    let save: (NookItem) -> Bool
    @State private var error = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("物品名称", text: $item.name)
                Picker("分类", selection: $item.category) {
                    ForEach(["家具","家电","收纳","厨具","服饰","其他"], id: \.self) { Text($0).tag($0) }
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
            .navigationTitle(item.preview ? "意向商品" : "自有物品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if save(item) { dismiss() } else { error = true }
                    }.disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                ![item.length,item.width,item.height].allSatisfy { (1...10000).contains($0) } || !(0...100000000).contains(item.value))
                }
            }
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
                NookScene(room: room, selected: nil, overhead: false, move: { _, _ in }, select: { _ in }).frame(height: 240)
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

private struct NookScene: UIViewRepresentable {
    let room: NookRoom
    let selected: UUID?
    let overhead: Bool
    let move: (Double, Double) -> Void
    let select: (UUID?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling4X
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
        view.allowsCameraControl = !overhead
        if coordinator.sceneKey == sceneKey { return }
        coordinator.sceneKey = sceneKey
        let scene = SCNScene()
        scene.background.contents = UIColor.systemGroupedBackground
        let wall: UIColor = room.finish.wall == "灰绿" ? .systemMint.withAlphaComponent(0.65) :
            room.finish.wall == "浅蓝" ? .systemBlue.withAlphaComponent(0.35) : UIColor(white: 0.91, alpha: 1)
        box(scene, width: room.length, height: 0.05, depth: room.width, at: SCNVector3(0,-0.025,0),
            color: room.finish.floor == "木地板" ? .brown : .systemGray4)
        box(scene, width: 0.05, height: room.height, depth: room.width, at: SCNVector3(-room.length/2,room.height/2,0), color: wall)
        box(scene, width: room.length, height: room.height, depth: 0.05, at: SCNVector3(0,room.height/2,-room.width/2), color: wall)
        for item in room.items {
            let height = item.height * item.scale / 100
            let node = box(scene, width: item.length * item.scale / 100, height: height, depth: item.width * item.scale / 100,
                           at: SCNVector3(item.x,height/2,item.z),
                           color: selected == item.id ? .systemOrange : item.preview ? .systemPurple : .systemTeal)
            node.name = item.id.uuidString
            node.opacity = item.preview ? 0.48 : 1
            node.eulerAngles.y = Float(-item.rotation * .pi / 180)
        }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        let extent = max(room.length, room.width, room.height)
        camera.camera?.zFar = extent * 10
        if overhead {
            camera.position = SCNVector3(0, extent * 2, 0)
            camera.eulerAngles.x = -.pi/2
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = extent * 1.35
        } else {
            camera.position = SCNVector3(extent * 0.95, extent * 0.95, extent * 1.3)
            camera.look(at: SCNVector3(0, room.height/4, 0))
        }
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 850
        ambient.light?.color = room.finish.light == "暖色" ? UIColor(red: 1, green: 0.81, blue: 0.62, alpha: 1) : UIColor.white
        scene.rootNode.addChildNode(ambient)
        view.scene = scene
        view.pointOfView = camera
    }

    private var sceneKey: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(SceneState(room: room, selected: selected, overhead: overhead))
    }
    private struct SceneState: Encodable { let room: NookRoom; let selected: UUID?; let overhead: Bool }

    @discardableResult private func box(_ scene: SCNScene, width: Double, height: Double, depth: Double,
                                      at position: SCNVector3, color: UIColor) -> SCNNode {
        let shape = SCNBox(width: width, height: height, length: depth, chamferRadius: 0)
        shape.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: shape)
        node.position = position
        scene.rootNode.addChildNode(node)
        return node
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: NookScene
        var sceneKey: Data?
        init(_ parent: NookScene) { self.parent = parent }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            parent.overhead && (gestureRecognizer is UIPinchGestureRecognizer || parent.selected != nil)
        }
        @objc func zoom(_ gesture: UIPinchGestureRecognizer) {
            guard let camera = (gesture.view as? SCNView)?.pointOfView?.camera else { return }
            camera.orthographicScale = min(160, max(0.5, camera.orthographicScale / gesture.scale))
            gesture.scale = 1
        }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let id = view.hitTest(gesture.location(in: view), options: nil).first?.node.name.flatMap(UUID.init(uuidString:))
            parent.select(id)
        }
        @objc func drag(_ gesture: UIPanGestureRecognizer) {
            guard parent.overhead, let id = parent.selected, let view = gesture.view as? SCNView,
                  let node = view.scene?.rootNode.childNode(withName: id.uuidString, recursively: false) else { return }
            let point = gesture.location(in: view)
            if gesture.state == .cancelled || gesture.state == .failed {
                if let item = parent.room.items.first(where: { $0.id == id }) {
                    node.position.x = Float(item.x)
                    node.position.z = Float(item.z)
                }
                return
            }
            let depth = view.projectPoint(SCNVector3Zero).z
            let next = view.unprojectPoint(SCNVector3(Float(point.x),Float(point.y),depth))
            guard next.x.isFinite, next.z.isFinite else { return }
            node.position.x = next.x
            node.position.z = next.z
            if gesture.state == .ended { parent.move(Double(next.x), Double(next.z)) }
        }
    }
}
