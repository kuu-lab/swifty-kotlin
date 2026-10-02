import Foundation

/// Read access to a Kotlin `.klib` library, packed (zip archive) or
/// unpacked (directory containing `<component>/manifest`).
///
/// A klib carries one or more *components* — top-level directories that
/// each contain a `manifest`. Libraries produced for a single target use
/// the conventional `default` component; `read(_:)` resolves paths relative
/// to the selected component root.
package struct KlibContainer {
    enum Storage {
        case archive(ZipArchive)
        case directory(root: URL)
    }

    /// Filesystem path, kept for diagnostics.
    package let path: String
    /// Name of the selected component directory (usually `"default"`).
    package let component: String
    private let storage: Storage

    package init(path: String) throws {
        self.path = path
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw KlibFormatError.unreadableContainer(path)
        }
        if isDirectory.boolValue {
            component = try Self.pickComponent(
                names: FileManager.default.subpaths(atPath: path) ?? [],
                hasManifest: { name in
                    var flag: ObjCBool = false
                    let manifestPath = url.appendingPathComponent("\(name)/manifest").path
                    return FileManager.default.fileExists(atPath: manifestPath, isDirectory: &flag)
                        && !flag.boolValue
                }
            )
            storage = .directory(root: url)
        } else {
            let archive = try ZipArchive(data: Data(contentsOf: url))
            component = try Self.pickComponent(
                names: archive.entries.map(\.name),
                hasManifest: { name in
                    archive.entries.contains { $0.name == "\(name)/manifest" && !$0.isDirectory }
                }
            )
            storage = .archive(archive)
        }
    }

    /// `manifest` of the selected component, parsed.
    package func manifest() throws -> KlibManifest {
        let bytes = try read("manifest")
        return try KlibManifest(contents: String(decoding: bytes, as: UTF8.self))
    }

    /// Component-relative entry paths, e.g. `ir/irDeclarations.knd`.
    package func entryPaths() -> [String] {
        let prefix = component + "/"
        switch storage {
        case .archive(let archive):
            return archive.entries.compactMap { entry in
                guard !entry.isDirectory, entry.name.hasPrefix(prefix) else { return nil }
                return String(entry.name.dropFirst(prefix.count))
            }
        case .directory(let root):
            let componentPath = root.appendingPathComponent(component).path
            guard let subpaths = FileManager.default.subpaths(atPath: componentPath) else { return [] }
            return subpaths.filter { subpath in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: componentPath + "/" + subpath, isDirectory: &isDirectory
                ) && !isDirectory.boolValue
            }.map { $0.replacingOccurrences(of: "\\", with: "/") }.sorted()
        }
    }

    package func contains(_ relativePath: String) -> Bool {
        switch storage {
        case .archive(let archive):
            guard let entry = archive.entry(named: component + "/" + relativePath) else { return false }
            return !entry.isDirectory
        case .directory:
            guard resolvedDirectoryURL(relativePath) != nil else { return false }
            return true
        }
    }

    /// Reads an entry relative to the component root (`ir/types.knt`,
    /// `manifest`, ...). Traversal (`..`, absolute paths) is rejected.
    package func read(_ relativePath: String) throws -> [UInt8] {
        switch storage {
        case .archive(let archive):
            let entryName = component + "/" + relativePath
            guard let entry = archive.entry(named: entryName), !entry.isDirectory else {
                throw KlibFormatError.entryNotFound(entryName)
            }
            return try archive.contents(of: entry)
        case .directory:
            guard let url = resolvedDirectoryURL(relativePath) else {
                throw KlibFormatError.unsafeEntryPath(relativePath)
            }
            guard let data = try? Data(contentsOf: url) else {
                throw KlibFormatError.entryNotFound(relativePath)
            }
            return Array(data)
        }
    }

    // MARK: - Internals

    /// Pick the component to read: `"default"` when present, otherwise the
    /// lexicographically first top-level directory containing a manifest.
    private static func pickComponent(
        names: [String],
        hasManifest: (String) -> Bool
    ) throws -> String {
        var components = Set<String>()
        for name in names {
            guard let slash = name.firstIndex(of: "/") else { continue }
            let top = String(name[..<slash])
            if hasManifest(top) { components.insert(top) }
        }
        if components.contains("default") { return "default" }
        if let first = components.sorted().first { return first }
        throw KlibFormatError.invalidKlibLayout("no component with a manifest entry")
    }

    private func resolvedDirectoryURL(_ relativePath: String) -> URL? {
        guard case .directory(let root) = storage else { return nil }
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let componentRoot = root.appendingPathComponent(component)
            .resolvingSymlinksInPath().standardizedFileURL
        let resolved = componentRoot.appendingPathComponent(relativePath)
            .resolvingSymlinksInPath().standardizedFileURL
        let rootPath = componentRoot.path.hasSuffix("/") ? componentRoot.path : componentRoot.path + "/"
        guard resolved.path.hasPrefix(rootPath),
              FileManager.default.fileExists(atPath: resolved.path)
        else { return nil }
        return resolved
    }
}
