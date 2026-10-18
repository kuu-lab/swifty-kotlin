import Foundation

package enum CompilerFileSystem {
    package static func containedURL(relativePath: String, under rootURL: URL) -> URL? {
        guard !relativePath.isEmpty else { return nil }
        let candidate = rootURL.appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard isContained(candidate, in: rootURL, allowRoot: false) else { return nil }
        return candidate
    }

    package static func isContained(
        _ candidate: URL,
        in root: URL,
        allowRoot: Bool = true
    ) -> Bool {
        let canonicalCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalCandidate.path != canonicalRoot.path else { return allowRoot }

        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        return canonicalCandidate.path.hasPrefix(rootPath)
    }

    package static func isRegularFile(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeRegular
    }
}
