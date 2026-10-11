#!/usr/bin/env swift
import Foundation
import WebKit
import AppKit

final class Runner: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let htmlURL: URL
    var finished = false
    var exitCode: Int32 = 1

    init(htmlURL: URL) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        self.htmlURL = htmlURL
        super.init()
        webView.navigationDelegate = self
    }

    func start() {
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            webView.evaluateJavaScript("document.body.innerText") { result, error in
                let text = (result as? String) ?? error?.localizedDescription ?? ""
                print(text)
                let passed = text.contains("Failed: 0")
                self.exitCode = passed ? 0 : 1
                self.finished = true
                CFRunLoopStop(CFRunLoopGetMain())
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fputs("Navigation failed: \(error)\n", stderr)
        finished = true
        CFRunLoopStop(CFRunLoopGetMain())
    }
}

let defaultHTML = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("YTDownloader/YTDownloaderExtension/Resources/content.test.html")
let htmlURL = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:)) ?? defaultHTML
guard FileManager.default.fileExists(atPath: htmlURL.path) else {
    fputs("Missing \(htmlURL.path)\n", stderr)
    exit(2)
}

_ = NSApplication.shared
let runner = Runner(htmlURL: htmlURL)
runner.start()
CFRunLoopRun()
exit(runner.exitCode)
