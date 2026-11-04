import AgentIdentityLocalization
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: SharePanel(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

@MainActor private final class ShareModel: ObservableObject {
    let context: NSExtensionContext?
    let catalog = DearShareInbox.catalog()
    @Published var activityID = ""
    @Published var working = false
    @Published var progress = 0.0
    @Published var message = ""

    init(context: NSExtensionContext?) {
        self.context = context
        activityID = catalog?.activities.first?.id ?? ""
    }

    func cancel() { context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }

    func share() async {
        guard !working, let catalog,
              let activity = catalog.activities.first(where: { $0.id == activityID }) else { return }
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty, providers.count <= 50 else {
            message = String(localized: "请选择 1 至 50 项照片或视频。", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)))
            return
        }
        working = true
        let directory: URL
        do {
            directory = try DearShareInbox.pendingRoot().appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            message = shareDisplayError(error); working = false; return
        }
        do {
            var items: [DearShareInbox.Item] = []
            for (index, provider) in providers.enumerated() {
                let movie = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .movie) == true }
                let image = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
                guard let type = movie ?? image else { throw NSError(domain: "DearShareInbox", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "包含不支持的文件类型。", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)))]) }
                let mediaType = movie == nil ? "image" : "video"
                if mediaType == "video" && UTType(type)?.conforms(to: .mpeg4Movie) != true &&
                    UTType(type)?.conforms(to: .quickTimeMovie) != true {
                    throw NSError(domain: "DearShareInbox", code: 5,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "当前只支持 MP4 或 MOV 视频。", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)))])
                }
                let suffix = UTType(type)?.preferredFilenameExtension ?? (mediaType == "video" ? "mov" : "jpg")
                let name = UUID().uuidString + "." + suffix
                let destination = directory.appendingPathComponent(name)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    provider.loadFileRepresentation(forTypeIdentifier: type) { source, error in
                        do {
                            if let error { throw error }
                            guard let source else { throw NSError(domain: "DearShareInbox", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "无法读取相册中的原文件。", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)))]) }
                            let length = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            let limit = mediaType == "video" ? 500 * 1024 * 1024 : 50 * 1024 * 1024
                            guard length > 0 && length <= limit else { throw NSError(domain: "DearShareInbox", code: 4,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "照片上限 50 MB，视频上限 500 MB。", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)))]) }
                            try FileManager.default.copyItem(at: source, to: destination)
                            continuation.resume()
                        } catch { continuation.resume(throwing: error) }
                    }
                }
                let displayName = provider.suggestedName ?? (mediaType == "video" ? String(localized: "相册视频", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard))) : String(localized: "相册照片", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard))))
                items.append(.init(fileName: name, displayName: displayName, mediaType: mediaType))
                progress = Double(index + 1) / Double(providers.count)
            }
            try DearShareInbox.save(.init(account: catalog.account, activityID: activity.id,
                                         tenantID: activity.tenantID, items: items), at: directory)
            context?.completeRequest(returningItems: nil)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            message = shareDisplayError(error)
            working = false
        }
    }
}

private struct SharePanel: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                if let activities = model.catalog?.activities, !activities.isEmpty {
                    Picker(String(localized: "分享到活动", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard))), selection: $model.activityID) {
                        ForEach(activities) { activity in
                            Text(activity.title).tag(activity.id)
                        }
                    }
                    Text(String(localized: "默认选择最近一次活动。完成后打开 Linko Moment，照片或视频会发布到该活动。", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard))))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "请先打开 Linko Moment，登录并进入活动页读取活动列表。", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard))))
                        .foregroundStyle(.secondary)
                }
                if model.working { ProgressView(value: model.progress) }
                if !model.message.isEmpty { Text(model.message).foregroundStyle(.red) }
            }
            .navigationTitle(String(localized: "分享到 Linko Moment", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard))))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)))) { model.cancel() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "加入分享", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)))) { Task { await model.share() } }
                        .disabled(model.working || model.activityID.isEmpty)
                }
            }
        }
    }
}

private func shareDisplayError(_ error: Error) -> String {
    let source = error as NSError
    if source.domain == "DearShareInbox" { return source.localizedDescription }
    return String(localized: "无法读取或保存分享文件，请重试。", bundle: AgentIdentityLanguage.appBundle(language: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)), locale: Locale(identifier: AgentIdentityLanguage.current(defaults: UserDefaults(suiteName: DearShareInbox.groupID) ?? .standard)))
}
