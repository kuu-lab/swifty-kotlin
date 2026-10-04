import Foundation

/// The stdlib mode a golden case compiles against (RF-GOLDEN-012).
///
/// Cases without a spec file keep the historical implicit behavior — the
/// worker uses `KSWIFTK_GOLDEN_STDLIB_LIBRARY` when present and falls back to
/// bundled-source injection when it is not. A case that declares a profile
/// instead pins the mode it verifies: an `.artifact` case fails when no
/// artifact path is available rather than silently downgrading to source.
public enum GoldenStdlibProfile: String, Sendable, CaseIterable {
    /// Resolve stdlib symbols from a prebuilt `.kklib` artifact.
    case artifact
    /// Compile the bundled Kotlin stdlib sources together with the case.
    case source
    /// Compile without stdlib (residual synthetic fallbacks only).
    case noStdlib = "no-stdlib"
}

/// Per-case golden spec (RF-GOLDEN-011/012), carried by an optional
/// `<name>.golden-spec` file adjacent to the case's `<name>.kt`.
///
/// Line format: `key=value`, one directive per line. Lines whose first
/// non-whitespace character is `#` are comments, blank lines are ignored.
/// The first directive must be `version=1`.
/// Recognized keys:
///
///   - `version=1`                — schema version, required, first directive
///   - `stdlib-profile=<profile>` — one of `artifact` / `source` / `no-stdlib`
///   - `target=<key>`             — a stdlib declaration this case is
///     responsible for, identified by its meaning key (the same string the
///     `call=` / `ref=` / `symbol fq=` fields render, e.g.
///     `kotlin.collections.toMap[kind=fun;recv=kotlin.collections.Map<out T0,T1>;params=;gen=2]`).
///     A bare FQName (`kotlin.Any`) is accepted when it resolves to exactly
///     one symbol.
///
/// Unknown keys, a missing or unsupported `version`, duplicate `target`
/// entries, and `target` without `stdlib-profile` are rejected — a spec that
/// does not parse cleanly must not silently downgrade the case to ordinary
/// output.
public struct GoldenHarnessCaseSpec: Sendable, Equatable {
    public static let specFileExtension = "golden-spec"
    public static let currentSchemaVersion = 1

    public let stdlibProfile: GoldenStdlibProfile?
    public let targets: [String]

    public init(stdlibProfile: GoldenStdlibProfile?, targets: [String]) {
        self.stdlibProfile = stdlibProfile
        self.targets = targets
    }

    /// The spec URL adjacent to a case source file (`foo.kt` →
    /// `foo.golden-spec`).
    public static func specURL(forSourceURL sourceURL: URL) -> URL {
        sourceURL.deletingPathExtension().appendingPathExtension(specFileExtension)
    }

    /// Loads the spec adjacent to `sourceURL`, or `nil` when no spec file
    /// exists. Throws on any malformed spec.
    public static func load(forSourceURL sourceURL: URL) throws -> GoldenHarnessCaseSpec? {
        let url = specURL(forSourceURL: sourceURL)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try parse(contents, path: url.path)
    }

    static func parse(_ contents: String, path: String) throws -> GoldenHarnessCaseSpec {
        var sawVersion = false
        var profile: GoldenStdlibProfile?
        var targets: [String] = []
        var seenTargets = Set<String>()

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            // `#` starts a comment only as the first non-whitespace
            // character — target keys may legitimately embed `#`.
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            guard let separator = line.firstIndex(of: "=") else {
                throw GoldenHarnessCaseSpecError.malformedLine(path: path, line: line)
            }
            let key = String(line[line.startIndex ..< separator])
            let value = String(line[line.index(after: separator)...])
            guard !value.isEmpty else {
                throw GoldenHarnessCaseSpecError.missingValue(path: path, key: key)
            }

            if !sawVersion {
                guard key == "version" else {
                    throw GoldenHarnessCaseSpecError.missingVersion(path: path)
                }
                guard value == "\(currentSchemaVersion)" else {
                    throw GoldenHarnessCaseSpecError.unsupportedVersion(path: path, version: value)
                }
                sawVersion = true
                continue
            }

            switch key {
            case "version":
                throw GoldenHarnessCaseSpecError.duplicateVersion(path: path)
            case "stdlib-profile":
                guard profile == nil else {
                    throw GoldenHarnessCaseSpecError.duplicateProfile(path: path)
                }
                guard let parsed = GoldenStdlibProfile(rawValue: value) else {
                    throw GoldenHarnessCaseSpecError.invalidProfile(path: path, value: value)
                }
                profile = parsed
            case "target":
                guard seenTargets.insert(value).inserted else {
                    throw GoldenHarnessCaseSpecError.duplicateTarget(path: path, target: value)
                }
                targets.append(value)
            default:
                throw GoldenHarnessCaseSpecError.unknownKey(path: path, key: key)
            }
        }

        guard sawVersion else {
            throw GoldenHarnessCaseSpecError.missingVersion(path: path)
        }
        guard !targets.isEmpty || profile != nil else {
            throw GoldenHarnessCaseSpecError.emptySpec(path: path)
        }
        if !targets.isEmpty {
            guard profile != nil else {
                throw GoldenHarnessCaseSpecError.targetsRequireProfile(path: path)
            }
        }
        return GoldenHarnessCaseSpec(stdlibProfile: profile, targets: targets)
    }
}

public enum GoldenHarnessCaseSpecError: Error, CustomStringConvertible {
    case missingVersion(path: String)
    case unsupportedVersion(path: String, version: String)
    case duplicateVersion(path: String)
    case malformedLine(path: String, line: String)
    case missingValue(path: String, key: String)
    case unknownKey(path: String, key: String)
    case invalidProfile(path: String, value: String)
    case duplicateProfile(path: String)
    case duplicateTarget(path: String, target: String)
    case targetsRequireProfile(path: String)
    case emptySpec(path: String)

    public var description: String {
        switch self {
        case let .missingVersion(path):
            return "\(path): first directive must be 'version=\(GoldenHarnessCaseSpec.currentSchemaVersion)'"
        case let .unsupportedVersion(path, version):
            return "\(path): unsupported golden-spec version '\(version)' (expected \(GoldenHarnessCaseSpec.currentSchemaVersion))"
        case let .duplicateVersion(path):
            return "\(path): duplicate 'version' directive"
        case let .malformedLine(path, line):
            return "\(path): malformed line '\(line)' (expected 'key=value')"
        case let .missingValue(path, key):
            return "\(path): directive '\(key)' requires a value"
        case let .unknownKey(path, key):
            return "\(path): unknown directive '\(key)'"
        case let .invalidProfile(path, value):
            let known = GoldenStdlibProfile.allCases.map(\.rawValue).joined(separator: ", ")
            return "\(path): invalid stdlib-profile '\(value)' (expected one of: \(known))"
        case let .duplicateProfile(path):
            return "\(path): duplicate 'stdlib-profile' directive"
        case let .duplicateTarget(path, target):
            return "\(path): duplicate target '\(target)'"
        case let .targetsRequireProfile(path):
            return "\(path): 'target' directives require an explicit 'stdlib-profile'"
        case let .emptySpec(path):
            return "\(path): spec declares neither 'stdlib-profile' nor 'target'"
        }
    }
}
