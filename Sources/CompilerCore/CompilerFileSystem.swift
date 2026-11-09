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
        return isCanonicalPathContained(canonicalCandidate, in: canonicalRoot, allowRoot: allowRoot)
    }

    /// Checks containment for URLs that callers have already resolved and standardized.
    package static func isCanonicalPathContained(
        _ candidate: URL,
        in root: URL,
        allowRoot: Bool = true
    ) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard candidatePath != rootPath else { return allowRoot }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(rootPrefix)
    }

    package static func isRegularFile(
        at url: URL) -> Bool {
        // `attributesOfItem` pays several xattr syscalls per file — the
        // stdlib artifact validator walks ~2k objects + inline-KIR blobs
        // per compile, so use a single stat(2) instead (symlink-following,
        // same as attributesOfItem).
        var info = stat()
        return url.path.withCString { stat($0, &info) == 0 }
            && (info.st_mode & S_IFMT) == S_IFREG
    }
}
