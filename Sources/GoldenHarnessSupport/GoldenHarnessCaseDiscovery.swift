import Foundation

struct GoldenHarnessCaseFile: Sendable {
    var sourcePath: String { sourceURL.path }
    let sourceURL: URL
    /// Parsed `<name>.golden-spec`, or nil when absent. A spec that failed to
    /// parse leaves this nil and records `specLoadError`; strict discovery and
    /// persistence validation surface that error before a golden is written.
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
    case inventoryValidation([String])

    var description: String {
        switch self {
        case let .missingSuiteDirectory(path):
            "Golden suite directory does not exist: \(path)"
        case let .noKtFiles(path):
            "No golden .kt files in \(path)"
        case let .inventoryValidation(violations):
            "Golden case inventory validation failed:\n- \(violations.joined(separator: "\n- "))"
        }
    }
}

/// A checked-in snapshot of the discovery universe. The counts are useful in
/// CI diagnostics, while the target contract sets make dedicated-case changes
/// reviewable without depending on a particular shard's batch contents.
public struct GoldenHarnessCaseInventory: Sendable, Equatable {
    public let caseCount: Int
    public let caseCountBySuite: [String: Int]
    public let caseCountByProfile: [String: Int]
    public let targetedCaseKeys: Set<String>
    public let targetContracts: Set<String>
}

public enum GoldenHarnessCaseDiscovery {
    static func loadCases(suite: GoldenHarnessGoldenSuite) throws -> [GoldenHarnessCaseFile] {
        try loadCases(
            suite: suite,
            directory: GoldenHarnessPaths.goldenCasesDirectory.appendingPathComponent(suite.rawValue, isDirectory: true)
        )
    }

    /// Loads and validates one suite from an explicit directory. The directory
    /// overload keeps negative inventory tests isolated from the checked-in
    /// corpus while exercising the same production discovery path.
    static func loadCases(
        suite: GoldenHarnessGoldenSuite,
        directory suiteURL: URL
    ) throws -> [GoldenHarnessCaseFile] {
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

        let caseFiles = sourceFiles.map { GoldenHarnessCaseFile(sourceURL: $0) }
        var violations: [String] = []

        for caseFile in caseFiles {
            violations.append(contentsOf: validationViolations(
                for: caseFile,
                suite: suite,
                requireExpectedGolden: true
            ))
        }

        let sourceNames = Set(sourceFiles.map(\.lastPathComponent))
        let entries = try fm.contentsOfDirectory(at: suiteURL, includingPropertiesForKeys: nil)
        for entry in entries where entry.pathExtension == GoldenHarnessCaseSpec.specFileExtension {
            let sourceName = entry.deletingPathExtension().lastPathComponent + ".kt"
            if !sourceNames.contains(sourceName) {
                violations.append("orphaned .golden-spec: \(entry.path)")
            }
        }

        var goldenOwners: [String: [String]] = [:]
        for caseFile in caseFiles {
            goldenOwners[caseFile.goldenURL.lastPathComponent, default: []].append(caseFile.basename)
        }
        for (goldenName, owners) in goldenOwners where owners.count > 1 {
            violations.append(
                "multiple .kt cases map to the same expected golden '\(goldenName)': \(owners.sorted())"
            )
        }

        let expectedGoldenNames = Set(goldenOwners.keys)
        for entry in entries where entry.pathExtension == "golden" {
            if !expectedGoldenNames.contains(entry.lastPathComponent) {
                violations.append("orphaned or stale .golden: \(entry.path)")
            }
        }

        guard violations.isEmpty else {
            throw GoldenHarnessCaseDiscoveryError.inventoryValidation(violations.sorted())
        }
        return caseFiles
    }

    /// Runs the complete discovery and ownership audit. This intentionally
    /// scans every suite before any batch/shard selection so a duplicate target
    /// in two different shards cannot evade validation.
    public static func preflightAllSuites() throws -> GoldenHarnessCaseInventory {
        try preflightAllSuites(in: GoldenHarnessPaths.goldenCasesDirectory)
    }

    static func preflightAllSuites(in rootURL: URL) throws -> GoldenHarnessCaseInventory {
        var casesBySuite: [(suite: GoldenHarnessGoldenSuite, cases: [GoldenHarnessCaseFile])] = []
        var violations: [String] = []

        for suite in GoldenHarnessGoldenSuite.allCases {
            let suiteURL = rootURL.appendingPathComponent(suite.rawValue, isDirectory: true)
            do {
                let cases = try loadCases(suite: suite, directory: suiteURL)
                casesBySuite.append((suite, cases))
            } catch {
                violations.append("\(suite.rawValue): \(error)")
            }
        }

        guard violations.isEmpty else {
            throw GoldenHarnessCaseDiscoveryError.inventoryValidation(violations.sorted())
        }

        var targetOwners: [String: [String]] = [:]
        var targetedCaseKeys = Set<String>()
        var targetContracts = Set<String>()

        for (suite, cases) in casesBySuite {
            for caseFile in cases {
                let expected = try expectedTargets(from: caseFile.goldenURL)
                let caseKey = "\(suite.rawValue)/\(caseFile.basename)"
                guard let spec = caseFile.spec else {
                    if expected.hasSection || !expected.keys.isEmpty {
                        violations.append("\(caseKey): expected golden contains stdlib target output but no valid .golden-spec is present")
                    }
                    continue
                }

                if expected.hasSection && expected.keys.isEmpty {
                    violations.append("\(caseKey): expected golden has an empty stdlib target section")
                }
                if !spec.targets.isEmpty {
                    targetedCaseKeys.insert(caseKey)
                }

                let resolvedTargets = resolveDeclaredTargets(
                    spec.targets,
                    against: expected.keys,
                    caseKey: caseKey,
                    violations: &violations
                )
                guard resolvedTargets.count == spec.targets.count else {
                    continue
                }
                if resolvedTargets != expected.keys {
                    let missing = resolvedTargets.subtracting(expected.keys).sorted()
                    let unexpected = expected.keys.subtracting(resolvedTargets).sorted()
                    if !missing.isEmpty {
                        violations.append("\(caseKey): target declarations missing from expected golden: \(missing)")
                    }
                    if !unexpected.isEmpty {
                        violations.append("\(caseKey): expected golden target output is not declared by the spec: \(unexpected)")
                    }
                    continue
                }

                guard let profile = spec.stdlibProfile else {
                    if !resolvedTargets.isEmpty {
                        violations.append("\(caseKey): target declarations require an explicit stdlib profile")
                    }
                    continue
                }
                for target in resolvedTargets {
                    let contract = "\(profile.rawValue)|\(target)"
                    targetOwners[contract, default: []].append(caseKey)
                    targetContracts.insert(contract)
                }
            }
        }

        for (contract, owners) in targetOwners where owners.count > 1 {
            violations.append(
                "duplicate stdlib target contract '\(contract)' owned by \(owners.sorted().joined(separator: ", ")); split the contract or document an explicit reason"
            )
        }

        guard violations.isEmpty else {
            throw GoldenHarnessCaseDiscoveryError.inventoryValidation(violations.sorted())
        }

        var caseCountBySuite: [String: Int] = [:]
        var caseCountByProfile: [String: Int] = [:]
        var caseCount = 0
        for (suite, cases) in casesBySuite {
            caseCountBySuite[suite.rawValue] = cases.count
            caseCount += cases.count
            for caseFile in cases {
                let profile = caseFile.spec?.stdlibProfile?.rawValue ?? "implicit"
                caseCountByProfile[profile, default: 0] += 1
            }
        }
        return GoldenHarnessCaseInventory(
            caseCount: caseCount,
            caseCountBySuite: caseCountBySuite,
            caseCountByProfile: caseCountByProfile,
            targetedCaseKeys: targetedCaseKeys,
            targetContracts: targetContracts
        )
    }

    /// Validates a case before direct rendering or persistence. Unlike the
    /// complete suite audit, this checks only the source's own adjacent files,
    /// which keeps ad-hoc temporary cases usable while still preventing a
    /// deleted spec or malformed spec from falling back to legacy output.
    static func validateCaseFile(
        _ caseFile: GoldenHarnessCaseFile,
        suite: GoldenHarnessGoldenSuite? = nil,
        requireExpectedGolden: Bool
    ) throws {
        let violations = validationViolations(
            for: caseFile,
            suite: suite,
            requireExpectedGolden: requireExpectedGolden
        )
        guard violations.isEmpty else {
            throw GoldenHarnessCaseDiscoveryError.inventoryValidation(violations.sorted())
        }
    }

    private static func validationViolations(
        for caseFile: GoldenHarnessCaseFile,
        suite: GoldenHarnessGoldenSuite?,
        requireExpectedGolden: Bool
    ) -> [String] {
        var violations: [String] = []
        if let specLoadError = caseFile.specLoadError {
            violations.append("invalid .golden-spec for \(caseFile.basename): \(specLoadError)")
        }
        if let suite, let spec = caseFile.spec, !spec.targets.isEmpty, suite != .sema {
            violations.append("\(caseFile.basename): target directives are only valid in the Sema suite")
        }

        // A profile-suffixed golden without its adjacent spec is the classic
        // deleted/renamed-spec failure: the case would otherwise appear to be
        // an ordinary case and a later UPDATE_GOLDEN could write the legacy
        // path. Check only names belonging to this source so ad-hoc rendering
        // of one case is not coupled to unrelated sibling fixtures.
        let baseName = caseFile.sourceURL.deletingPathExtension().lastPathComponent
        let relatedGoldenNames = Set(
            ["\(baseName).golden"]
                + GoldenStdlibProfile.allCases.map { "\(baseName).\($0.rawValue).golden" }
        )
        let expectedGoldenName = caseFile.goldenURL.lastPathComponent
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: caseFile.sourceURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ) {
            for entry in entries where relatedGoldenNames.contains(entry.lastPathComponent) {
                if entry.lastPathComponent != expectedGoldenName {
                    violations.append("stale or mismatched profile golden for \(caseFile.basename): \(entry.path)")
                }
            }
        }

        let fm = FileManager.default
        if requireExpectedGolden {
            guard fm.fileExists(atPath: caseFile.goldenURL.path) else {
                violations.append("missing expected golden for \(caseFile.basename): \(caseFile.goldenURL.path)")
                return violations
            }
            do {
                _ = try String(contentsOf: caseFile.goldenURL, encoding: .utf8)
            } catch {
                violations.append("expected golden is not readable UTF-8 for \(caseFile.basename): \(caseFile.goldenURL.path) (\(error))")
            }
        }
        return violations
    }

    private struct ExpectedTargets {
        let hasSection: Bool
        let keys: Set<String>
    }

    private static func expectedTargets(from url: URL) throws -> ExpectedTargets {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var hasSection = false
        var inSection = false
        var keys = Set<String>()
        var violations: [String] = []

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line == "section stdlib-targets" {
                if hasSection {
                    violations.append("duplicate stdlib target section")
                }
                hasSection = true
                inSection = true
                continue
            }
            if inSection && line.hasPrefix("section ") {
                inSection = false
                continue
            }
            guard inSection, !line.isEmpty else { continue }

            let prefix = "target fq="
            guard line.hasPrefix(prefix) else {
                violations.append("malformed line in stdlib target section: \(line)")
                continue
            }
            let rest = String(line.dropFirst(prefix.count))
            guard let separator = rest.range(of: " origin=") else {
                violations.append("target line has no origin field: \(line)")
                continue
            }
            let key = String(rest[..<separator.lowerBound])
            guard !key.isEmpty else {
                violations.append("target line has an empty meaning key: \(line)")
                continue
            }
            guard keys.insert(key).inserted else {
                violations.append("duplicate target output in expected golden: \(key)")
                continue
            }
        }

        guard violations.isEmpty else {
            throw GoldenHarnessCaseDiscoveryError.inventoryValidation(
                violations.map { "\(url.path): \($0)" }
            )
        }
        return ExpectedTargets(hasSection: hasSection, keys: keys)
    }

    private static func resolveDeclaredTargets(
        _ declaredTargets: [String],
        against expectedKeys: Set<String>,
        caseKey: String,
        violations: inout [String]
    ) -> Set<String> {
        var resolved = Set<String>()
        for target in declaredTargets {
            let matches: [String]
            if target.contains("[") {
                matches = expectedKeys.contains(target) ? [target] : []
            } else {
                matches = expectedKeys.filter { key in
                    key.split(separator: "[", maxSplits: 1).first.map(String.init) == target
                }.sorted()
            }

            guard matches.count == 1, let match = matches.first else {
                if matches.isEmpty {
                    violations.append("\(caseKey): declared target '\(target)' is absent from its expected golden")
                } else {
                    violations.append("\(caseKey): bare target '\(target)' is ambiguous in its expected golden: \(matches)")
                }
                continue
            }
            guard resolved.insert(match).inserted else {
                violations.append("\(caseKey): multiple target declarations resolve to '\(match)'")
                continue
            }
        }
        return resolved
    }
}
