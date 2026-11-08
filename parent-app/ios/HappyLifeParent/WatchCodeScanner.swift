import AgentIdentity
import AgentIdentityHTTP
import SwiftUI
import VisionKit
import AVFoundation

struct WatchCodeScanner: View {
    var loginOrigin: URL? = nil
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ready = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Group {
                if ready {
                    WatchScannerCamera(loginOrigin: loginOrigin) { code in
                        onCode(code)
                        dismiss()
                    } onError: { text in
                        ready = false
                        message = text
                    }
                } else if let message {
                    ContentUnavailableView(String(localized: "无法扫描", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "camera", description: Text(message))
                } else { ProgressView(String(localized: "正在打开相机…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            }
            .navigationTitle(loginOrigin == nil ? String(localized: "扫描手表二维码", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "扫码登录", bundle: AgentIdentityLanguage.appBundle()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { dismiss() } } }
            .safeAreaInset(edge: .bottom) { Text(loginOrigin == nil ? String(localized: "对准手表上的配对二维码，识别后返回确认绑定。", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "扫描手表登录二维码，核对配对码后确认登录。", bundle: AgentIdentityLanguage.appBundle())) .font(.footnote).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
            .task {
                guard DataScannerViewController.isSupported else {
                    message = String(localized: "此设备不支持扫描，请返回手动输入手表设备码。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return
                }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                guard allowed, DataScannerViewController.isAvailable else {
                    message = String(localized: "请在系统设置中允许 Linko Moment 使用相机，或返回手动输入设备码。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return
                }
                ready = true
            }
        }
    }
}

private struct WatchScannerCamera: UIViewControllerRepresentable {
    let loginOrigin: URL?
    let onCode: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(loginOrigin: loginOrigin, onCode: onCode, onError: onError) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], recognizesMultipleItems: false, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning, !context.coordinator.finished else { return }
        do { try scanner.startScanning() }
        catch { DispatchQueue.main.async { onError(String(localized: "相机暂时无法使用，请重试或手动输入设备码。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) } }
    }
    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        coordinator.finished = true
        scanner.stopScanning()
        scanner.delegate = nil
    }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let loginOrigin: URL?
        let onCode: (String) -> Void
        let onError: (String) -> Void
        var finished = false
        init(loginOrigin: URL?, onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) { self.loginOrigin = loginOrigin; self.onCode = onCode; self.onError = onError }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let text = barcode.payloadStringValue else { continue }
                finished = true
                scanner.stopScanning()
                if let origin = loginOrigin, let url = AgentIdentityDeviceLogin.approvalURL(from: text, origin: origin) { onCode(url.absoluteString) }
                else if loginOrigin == nil, let code = WatchPairingCode.parse(text) { onCode(code) }
                else { onError(String(localized: "这不是有效的手表配对二维码，请返回重试或手动输入设备码。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                return
            }
        }
        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !finished else { return }
            finished = true
            scanner.stopScanning()
            onError(String(localized: "扫描已中断，请返回重试或手动输入设备码。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        }
    }
}
