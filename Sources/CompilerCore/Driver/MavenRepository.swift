import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

package enum MavenResolutionError: Error, CustomStringConvertible {
    case invalidCoordinate(String)
    case notFound(String, repositories: [String])
    case offline(String)
    case download(String, detail: String)
    case checksum(String)
    case metadata(String, detail: String)

    package var description: String {
        switch self {
        case let .invalidCoordinate(text):
            "Invalid Maven coordinate '\(text)'; expected group:artifact:version."
        case let .notFound(file, repositories):
            "\(file) was not found in \(repositories.joined(separator: ", "))."
        case let .offline(file):
            "\(file) is not in the Maven cache and --offline forbids downloading it."
        case let .download(url, detail):
            "Cannot download \(url): \(detail)"
        case let .checksum(url):
            "SHA-1 checksum mismatch for \(url)."
        case let .metadata(coordinate, detail):
            "Cannot read Maven metadata for \(coordinate): \(detail)"
        }
    }
}

/// Fetches immutable release artifacts from Maven repositories into a local
/// cache laid out like a Maven repository. Release coordinates never change
/// content, so a cached file is reused without revalidation; a `.missing`
/// marker records files that no repository serves (for example `.module`
/// metadata that POM-only artifacts lack) so later builds skip the lookups.
package struct MavenRepositorySet: Sendable {
    /// Google's Maven repository hosts AndroidX; Maven Central the rest.
    /// This is the `google()` + `mavenCentral()` pair Android projects use.
    package static let defaultRepositories = [
        "https://dl.google.com/dl/android/maven2",
        "https://repo.maven.apache.org/maven2",
    ]

    package static var defaultCacheDirectory: String {
        if let path = ProcessInfo.processInfo.environment["KSWIFTK_MAVEN_CACHE"], !path.isEmpty {
            return path
        }
        return NSHomeDirectory() + "/.kswiftk/maven"
    }

    package let repositories: [String]
    package let cacheDirectory: URL
    package let offline: Bool

    package init(repositories: [String], cacheDirectory: String, offline: Bool) {
        self.repositories = (repositories.isEmpty ? Self.defaultRepositories : repositories).map {
            $0.hasSuffix("/") ? String($0.dropLast()) : $0
        }
        self.cacheDirectory = URL(fileURLWithPath: cacheDirectory, isDirectory: true).standardizedFileURL
        self.offline = offline
    }

    /// Local path of `<artifact>-<version><suffix>`, or nil when no
    /// repository has it.
    package func fetch(_ coordinate: MavenCoordinate, suffix: String) throws -> URL? {
        let relative = coordinate.directory + "/" + coordinate.fileName(suffix)
        let cached = cacheDirectory.appendingPathComponent(relative)
        let missing = cached.appendingPathExtension("missing")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cached.path) { return cached }
        if fileManager.fileExists(atPath: missing.path) { return nil }
        if offline { throw MavenResolutionError.offline(relative) }

        try fileManager.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        for repository in repositories {
            let url = repository + "/" + relative
            guard let data = try download(url) else { continue }
            if let checksum = try download(url + ".sha1") {
                try verifySHA1(data, expected: checksum, url: url)
            }
            // Write beside the destination and rename so a concurrent
            // build never observes a partially written artifact.
            let temporary = cached.appendingPathExtension("part-\(UUID().uuidString)")
            try data.write(to: temporary)
            if fileManager.fileExists(atPath: cached.path) {
                try? fileManager.removeItem(at: temporary)
            } else {
                do {
                    try fileManager.moveItem(at: temporary, to: cached)
                } catch where fileManager.fileExists(atPath: cached.path) {
                    try? fileManager.removeItem(at: temporary)
                }
            }
            return cached
        }
        // Only optional metadata is remembered as absent: a missing POM or
        // artifact may appear once the user adds the repository serving it.
        if suffix == ".module" { try? Data().write(to: missing) }
        return nil
    }

    /// Like `fetch`, but a missing file is an error.
    package func require(_ coordinate: MavenCoordinate, suffix: String) throws -> URL {
        guard let file = try fetch(coordinate, suffix: suffix) else {
            throw MavenResolutionError.notFound(coordinate.fileName(suffix), repositories: repositories)
        }
        return file
    }

    /// Returns nil for 404/410 (absent), throws for every other failure.
    private func download(_ address: String) throws -> Data? {
        guard let url = URL(string: address) else {
            throw MavenResolutionError.download(address, detail: "invalid URL")
        }
        if url.isFileURL {
            return FileManager.default.contents(atPath: url.path)
        }
        let result = HTTPResult()
        let semaphore = DispatchSemaphore(value: 0)
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("kswiftc", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            result.data = data
            result.status = (response as? HTTPURLResponse)?.statusCode
            result.error = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        if let error = result.error {
            throw MavenResolutionError.download(address, detail: error.localizedDescription)
        }
        switch result.status ?? 0 {
        case 200: return result.data ?? Data()
        case 404, 410: return nil
        case let status: throw MavenResolutionError.download(address, detail: "HTTP \(status)")
        }
    }

    private func verifySHA1(_ data: Data, expected: Data, url: String) throws {
        // `.sha1` files hold the hex digest, sometimes followed by a path.
        guard let text = String(data: expected, encoding: .utf8)?
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }).first
        else { return }
        #if canImport(CryptoKit) || canImport(Crypto)
        let actual = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == text.lowercased() else { throw MavenResolutionError.checksum(url) }
        #else
        _ = text
        #endif
    }

    private final class HTTPResult: @unchecked Sendable {
        var data: Data?
        var status: Int?
        var error: Error?
    }
}
