import SwiftUI
import AppKit

struct AppIconView: View {
    let bundleURL: URL
    var size: CGFloat = 32

    var body: some View {
        if FileManager.default.fileExists(atPath: bundleURL.path),
           let image = NSWorkspace.shared.icon(forFile: bundleURL.path) as NSImage? {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
