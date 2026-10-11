#!/usr/bin/env swift
import Foundation
import WebKit
import AppKit

final class Snap: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let htmlURL: URL
    let outURL: URL
    var done = false

    init(htmlURL: URL, outURL: URL) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 620), configuration: config)
        self.htmlURL = htmlURL
        self.outURL = outURL
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { image, error in
                if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: self.outURL)
                    print("wrote \(self.outURL.path)")
                } else {
                    fputs("snapshot failed: \(error?.localizedDescription ?? "unknown")\n", stderr)
                }
                self.done = true
                CFRunLoopStop(CFRunLoopGetMain())
            }
        }
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let html = root.appendingPathComponent("Scripts/yd-button-preview.html")
let out = root.appendingPathComponent("Scripts/yd-button-preview.png")
_ = NSApplication.shared
let snap = Snap(htmlURL: html, outURL: out)
snap.webView.loadFileURL(html, allowingReadAccessTo: root)
CFRunLoopRun()
exit(snap.done ? 0 : 1)
