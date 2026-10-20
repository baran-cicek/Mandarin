import UniformTypeIdentifiers

extension UTType {
    /// Looks a type up by system identifier, then by file extension, and as a
    /// last resort declares a private one. Some systems (for example CI
    /// runners or Macs without a video player installed) do not know every
    /// identifier, and a force-unwrap there would crash the app at launch.
    static func known(_ identifier: String?, ext: String, conformingTo parent: UTType = .data) -> UTType {
        if let identifier, let type = UTType(identifier) { return type }
        if let type = UTType(filenameExtension: ext) { return type }
        return UTType(exportedAs: "\(AppIdentity.bundleID).format.\(ext)", conformingTo: parent)
    }
}
