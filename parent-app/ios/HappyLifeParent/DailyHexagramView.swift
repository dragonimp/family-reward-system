import SwiftUI
import WebKit

struct DailyHexagramView: UIViewRepresentable {
    func makeCoordinator() -> NavigationGuard { NavigationGuard() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let stored = UserDefaults.standard.dictionary(forKey: "moment.yigua.data") ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: stored)) ?? Data("{}".utf8)
        let initial = String(decoding: data, as: UTF8.self)
        configuration.userContentController.add(context.coordinator, name: "yiguaStorage")
        let source = """
        (() => {
            const state = \(initial);
            window.yiguaStore = {
                getItem: key => state[key] ?? null,
                setItem(key, value) {
                    state[key] = value;
                    window.webkit.messageHandlers.yiguaStorage.postMessage({key, value});
                }
            };
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        if let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "yigua") {
            context.coordinator.page = page
            view.loadFileURL(page, allowingReadAccessTo: page)
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: NavigationGuard) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "yiguaStorage")
    }

    final class NavigationGuard: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var page: URL?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url == page,
                  let payload = message.body as? [String: String],
                  let key = payload["key"], ["yigua:history", "yigua:unlocked", "yigua:collected"].contains(key),
                  let value = payload["value"], value.utf8.count <= 512_000 else { return }
            var stored = UserDefaults.standard.dictionary(forKey: "moment.yigua.data") ?? [:]
            stored[key] = value
            UserDefaults.standard.set(stored, forKey: "moment.yigua.data")
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url == page && page != nil ? .allow : .cancel)
        }
    }
}
