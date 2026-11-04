import AgentIdentity
import SwiftUI
import VisionKit
import AVFoundation

struct WatchCodeScanner: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ready = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Group {
                if ready {
                    WatchScannerCamera { code in
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
            .navigationTitle(String(localized: "扫描手表二维码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { dismiss() } } }
            .safeAreaInset(edge: .bottom) { Text(String(localized: "对准手表上的配对二维码，识别后返回确认绑定。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .font(.footnote).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
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
    let onCode: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }
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
        let onCode: (String) -> Void
        let onError: (String) -> Void
        var finished = false
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) { self.onCode = onCode; self.onError = onError }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let text = barcode.payloadStringValue else { continue }
                finished = true
                scanner.stopScanning()
                if let code = WatchPairingCode.parse(text) { onCode(code) }
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
