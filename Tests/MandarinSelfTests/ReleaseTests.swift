import AppKit
import Foundation
import Mandarin

/// Repo root, derived from this file's location (Tests/MandarinSelfTests/).
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
func runReleaseTests() async {
    print("\nRelease: identity, icon, repo hygiene")

    let plist = NSDictionary(contentsOf: repoRoot.appendingPathComponent("Resources/Info.plist")) as? [String: Any] ?? [:]
    check("AppIdentity.name matches Info.plist CFBundleName/DisplayName/Executable",
          plist["CFBundleName"] as? String == AppIdentity.name
          && plist["CFBundleDisplayName"] as? String == AppIdentity.name
          && plist["CFBundleExecutable"] as? String == AppIdentity.name)
    check("AppIdentity.bundleID matches Info.plist CFBundleIdentifier",
          plist["CFBundleIdentifier"] as? String == AppIdentity.bundleID)

    let readme = (try? String(contentsOf: repoRoot.appendingPathComponent("README.md"))) ?? ""
    check("README title is the app name", readme.hasPrefix("# \(AppIdentity.name)"))

    for size in [16, 32] as [CGFloat] {
        let image = MenuBarIcon.image(pointSize: size)
        check("Menu-bar icon is a template image at \(Int(size)) pt", image.isTemplate)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let c = Int(size) / 2
        let centreAlpha = rep.colorAt(x: c, y: c)?.alphaComponent ?? 0
        let cornerAlpha = rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1
        check("Menu-bar icon draws a dot in the centre and stays empty at the corner (\(Int(size)) px)",
              centreAlpha > 0.9 && cornerAlpha < 0.1)
    }

    let offenders = scanForForbiddenText()
    check("No forbidden word or personal data in source files (\(offenders.joined(separator: ", ")))", offenders.isEmpty)

    let gitignore = (try? String(contentsOf: repoRoot.appendingPathComponent(".gitignore"))) ?? ""
    check(".gitignore covers session exports", gitignore.contains("*local-command-caveat*.txt"))
}

/// Forbidden word and personal data must not appear in tracked sources.
func scanForForbiddenText() -> [String] {
    let forbidden = ["tange" + "rine", "Bar" + "ans-Air", "/Users/" + "bar" + "an", "gmail" + ".com", "bar" + "an", "cic" + "ek", "fritz" + ".box"]
    var offenders: [String] = []
    let fm = FileManager.default
    let skipDirs: Set<String> = [".build", ".git", "dist", "clean-export"]
    guard let walker = fm.enumerator(at: repoRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
    while let url = walker.nextObject() as? URL {
        let name = url.lastPathComponent
        if skipDirs.contains(name) { walker.skipDescendants(); continue }
        guard ["swift", "md", "sh", "plist", "yml", "yaml", "txt", "svg"].contains(url.pathExtension)
                || name == "Brewfile" || name == "Makefile" || name == "LICENSE" else { continue }
        if name.contains("local-command-caveat") || name == "ReleaseTests.swift" { continue }
        guard var text = try? String(contentsOf: url) else { continue }
        // The public repository URL legitimately contains the owner's GitHub handle.
        text = text.replacingOccurrences(of: "(?i)https://github\\.com/[A-Za-z0-9-]+/mandarin(\\.git)?", with: "<repo-url>", options: .regularExpression)
        let lower = text.lowercased()
        for word in forbidden where lower.contains(word.lowercased()) {
            offenders.append("\(name): \(word)")
        }
    }
    return offenders
}
