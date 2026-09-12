import Foundation

struct GoldenHarnessCaseFile: Sendable {
    var sourcePath: String { sourceURL.path }
    let sourceURL: URL
    /// Parsed `<name>.golden-spec`, or nil when absent. A spec that failed to
    /// parse leaves this nil and records `specLoadError`; `goldenURL` then
    /// falls back to the legacy name so one broken spec cannot take down
    /// discovery for the whole suite.
    let spec: GoldenHarnessCaseSpec?
    let specLoadError: String?
    /// Spec-carrying cases pin their stdlib profile into the golden filename
    /// (`<name>.<profile>.golden`, RF-GOLDEN-012) so the same fixture's
    /// artifact/source/no-stdlib snapshots never overwrite each other.
    var goldenURL: URL {
        let base = sourceURL.deletingPathExtension()
        guard let profile = spec?.stdlibProfile else {
            return base.appendingPathExtension("golden")
        }
        return base.appendingPathExtension("\(profile.rawValue).golden")
    }
    var basename: String { sourceURL.lastPathComponent }

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        do {
            spec = try GoldenHarnessCaseSpec.load(forSourceURL: sourceURL)
            specLoadError = nil
        } catch {
            spec = nil
            specLoadError = String(describing: error)
        }
    }
}

enum GoldenHarnessCaseDiscoveryError: Error, CustomStringConvertible {
    case missingSuiteDirectory(String)
    case noKtFiles(String)

    var description: String {
        switch self {
        case let .missingSuiteDirectory(path):
            "Golden suite directory does not exist: \(path)"
        case let .noKtFiles(path):
            "No golden .kt files in \(path)"
        }
    }
}

enum GoldenHarnessCaseDiscovery {
    static func loadCases(suite: GoldenHarnessGoldenSuite) throws -> [GoldenHarnessCaseFile] {
        let suiteURL = GoldenHarnessPaths.goldenCasesDirectory.appendingPathComponent(suite.rawValue, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: suiteURL.path) else {
            throw GoldenHarnessCaseDiscoveryError.missingSuiteDirectory(suiteURL.path)
        }

        let sourceFiles = try fm.contentsOfDirectory(at: suiteURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "kt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sourceFiles.isEmpty else {
            throw GoldenHarnessCaseDiscoveryError.noKtFiles(suiteURL.path)
        }
        return sourceFiles.map { GoldenHarnessCaseFile(sourceURL: $0) }
    }
}
