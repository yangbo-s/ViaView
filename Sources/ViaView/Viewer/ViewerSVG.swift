import AppKit
import ViewerCore
@preconcurrency import WebKit

extension ViewerController {
    func showSVG(_ url: URL, serial: Int) {
        showMessage("正在绘制矢量图像…", detail: url.lastPathComponent, loading: true)
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let configuration = WKWebViewConfiguration(); configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.websiteDataStore = .nonPersistent()
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "ViaViewOfflineSVG", encodedContentRuleList: "[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^about:\"},\"action\":{\"type\":\"ignore-previous-rules\"}},{\"trigger\":{\"url-filter\":\"^data:\"},\"action\":{\"type\":\"ignore-previous-rules\"}}]") { [weak self] rules, error in
                guard let self, self.loadSerial == serial else { return }
                guard let rules, error == nil else { self.showMessage("SVG 渲染器无法初始化", detail: error?.localizedDescription ?? "离线规则加载失败", loading: false); return }
                configuration.userContentController.add(rules)
                self.web?.removeFromSuperview()
                let browser = WKWebView(frame: NSRect(origin: .zero, size: self.asset?.image.size ?? NSSize(width: 640, height: 480)), configuration: configuration); self.web = browser; browser.underPageBackgroundColor = .clear; browser.navigationDelegate = self
                self.scroll.documentView = browser
                self.scroll.isHidden = false
                self.prepareImageWindow()
                browser.loadHTMLString("<html><head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'\"><meta name='viewport' content='width=device-width'><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}svg{display:block;width:100%;height:100%;object-fit:contain}</style></head><body>\(text)</body></html>", baseURL: nil)
            }
        } catch { showMessage("SVG 无法读取", detail: error.localizedDescription, loading: false) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        decisionHandler(scheme == "about" || scheme == "data" ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === web, asset?.isSVG == true else { return }
        empty.isHidden = true; progress.stopAnimation(nil)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { svgFailed(webView, error: error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { svgFailed(webView, error: error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        svgFailed(webView, error: ViewerError.decode(gallery.current?.lastPathComponent ?? "SVG"))
    }
    func svgFailed(_ browser: WKWebView, error: Error) {
        guard browser === web, asset?.isSVG == true else { return }
        showMessage("SVG 无法显示", detail: error.localizedDescription + "\n可以重新打开或继续切换图片。", loading: false)
    }
}
