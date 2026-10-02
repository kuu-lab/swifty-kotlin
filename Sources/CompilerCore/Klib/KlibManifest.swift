import Foundation

/// Java `properties` parser for `.klib` manifest files.
///
/// Kotlin writes `manifest` with `java.util.Properties.store`: one
/// `key=value` (or `key: value`) per line, `#`/`!` comment lines, `\`
/// line continuations, and `\t \n \r \f \\ \uXXXX` escapes. Duplicate keys
/// keep the last value, matching `Properties.load` semantics.
package enum JavaProperties {
    package static func parse(_ text: String) throws -> [(key: String, value: String)] {
        var pairs: [(String, String)] = []
        var logical = ""
        var continuation = false

        for physicalLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(physicalLine)
            if line.hasSuffix("\r") { line.removeLast() }
            if continuation {
                // Leading whitespace on a continuation line is skipped.
                logical += line.drop(while: { $0 == " " || $0 == "\t" || $0 == "\u{0C}" })
            } else {
                // Leading whitespace does not start a new property.
                line = String(line.drop(while: { $0 == " " || $0 == "\t" || $0 == "\u{0C}" }))
                if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!") {
                    continue
                }
                logical = line
            }
            if hasContinuation(logical) {
                logical.removeLast()
                continuation = true
                continue
            }
            continuation = false
            pairs.append(splitProperty(logical))
        }
        if continuation && !logical.isEmpty {
            pairs.append(splitProperty(logical))
        }
        return pairs
    }

    /// True when the line ends with an odd number of `\` (continuation).
    /// Only the trailing run counts — `\t` earlier in the line is unrelated.
    private static func hasContinuation(_ line: String) -> Bool {
        var backslashes = 0
        for ch in line.reversed() {
            guard ch == "\\" else { break }
            backslashes += 1
        }
        return backslashes % 2 == 1
    }

    private static func splitProperty(_ line: String) -> (key: String, value: String) {
        // First unescaped `=`, `:` or whitespace separates key and value.
        var keyEnd = line.startIndex
        var escaped = false
        scan: while keyEnd < line.endIndex {
            let ch = line[keyEnd]
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "=" || ch == ":" || ch == " " || ch == "\t" || ch == "\u{0C}" {
                break
            }
            keyEnd = line.index(after: keyEnd)
        }
        var valueStart = keyEnd
        while valueStart < line.endIndex {
            let ch = line[valueStart]
            if ch == " " || ch == "\t" || ch == "\u{0C}" || ch == "=" || ch == ":" {
                valueStart = line.index(after: valueStart)
            } else {
                break
            }
        }
        return (unescape(String(line[..<keyEnd])), unescape(String(line[valueStart...])))
    }

    private static func unescape(_ string: String) -> String {
        guard string.contains("\\") else { return string }
        var result = ""
        var i = string.startIndex
        while i < string.endIndex {
            let ch = string[i]
            guard ch == "\\", string.index(after: i) < string.endIndex else {
                result.append(ch)
                i = string.index(after: i)
                continue
            }
            i = string.index(after: i)
            let esc = string[i]
            i = string.index(after: i)
            switch esc {
            case "t": result.append("\t")
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "f": result.append("\u{0C}")
            case "u":
                var code = 0
                for _ in 0 ..< 4 where i < string.endIndex {
                    code = code * 16 + (string[i].hexDigitValue ?? 0)
                    i = string.index(after: i)
                }
                result.append(Character(UnicodeScalar(code) ?? "\u{FFFD}"))
            default:
                result.append(esc)
            }
        }
        return result
    }
}

/// Typed view of a Kotlin `.klib` `manifest` file (Java properties format).
///
/// Reference fields written by the Kotlin compiler include `unique_name`,
/// `compiler_version`, `abi_version`, `metadata_version`, `depends`,
/// `builtins_platform`, `ir_signature_versions`, `library_version` and the
/// platform target keys (`native_targets`, `wasm_targets`, `jsOutputName`).
package struct KlibManifest {
    /// `x.y.z` style version; the patch component is optional.
    package struct Version: Comparable, CustomStringConvertible {
        package let major: Int
        package let minor: Int
        package let patch: Int

        package init?(_ string: String) {
            let parts = string.split(separator: ".").map(String.init)
            guard (2 ... 3).contains(parts.count),
                  let major = Int(parts[0]),
                  let minor = Int(parts[1])
            else { return nil }
            // Kotlin may suffix versions ("2.4.20-dev-7885"); keep the
            // leading numeric component of the patch field.
            let patchField = parts.count > 2 ? parts[2] : "0"
            let digits = patchField.prefix(while: { $0.isNumber })
            self.major = major
            self.minor = minor
            self.patch = Int(digits) ?? 0
        }

        package static func < (lhs: Version, rhs: Version) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }

        package var description: String { "\(major).\(minor).\(patch)" }
    }

    /// How well this compiler can consume the klib.
    package enum Compatibility: Equatable {
        /// Produced by a Kotlin version whose IR layout we fully support.
        case supported
        /// Newer than the supported track; import proceeds best-effort and
        /// the caller should surface `reason` as a warning.
        case bestEffort(reason: String)
        /// Cannot be imported; `reason` should be surfaced as an error.
        case unsupported(reason: String)
    }

    package let uniqueName: String
    package let compilerVersion: Version?
    package let abiVersion: Version?
    package let metadataVersion: Version?
    package let libraryVersion: String?
    package let irSignatureVersions: Set<Int>
    /// `depends` — space-separated `unique_name`s of required libraries.
    package let depends: [String]
    package let builtinsPlatform: String?
    /// All remaining key/value pairs, last value wins.
    package let properties: [String: String]

    package init(contents: String) throws {
        var props: [String: String] = [:]
        for (key, value) in try JavaProperties.parse(contents) {
            props[key] = value
        }
        self.properties = props
        guard let uniqueName = props["unique_name"], !uniqueName.isEmpty else {
            throw KlibFormatError.missingManifestKey("unique_name")
        }
        self.uniqueName = uniqueName
        self.compilerVersion = props["compiler_version"].flatMap(Version.init)
        self.abiVersion = props["abi_version"].flatMap(Version.init)
        self.metadataVersion = props["metadata_version"].flatMap(Version.init)
        self.libraryVersion = props["library_version"]
        self.builtinsPlatform = props["builtins_platform"]
        self.irSignatureVersions = Set(
            (props["ir_signature_versions"] ?? "")
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .compactMap { Int($0) }
        )
        self.depends = (props["depends"] ?? "")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
    }

    /// Version gate for the IR reader. KSwiftK targets Kotlin 2.3.x;
    /// `abi_version` "2.3.*" is the supported track. Kotlin 2.4 keeps the
    /// same chunk layout but adds varint-sized tables, which the IR readers
    /// handle, so 2.4.x is accepted best-effort. Anything else is rejected.
    package var compatibility: Compatibility {
        guard let abiVersion else {
            return .unsupported(reason: "manifest is missing 'abi_version'")
        }
        switch (abiVersion.major, abiVersion.minor) {
        case (2, 3):
            break
        case (2, 4):
            return .bestEffort(
                reason: "klib '\(uniqueName)' has abi_version \(abiVersion) newer than the supported 2.3.x track; import is best-effort"
            )
        default:
            return .unsupported(
                reason: "klib '\(uniqueName)' has unsupported abi_version \(abiVersion) (expected 2.3.x)"
            )
        }
        guard irSignatureVersions.contains(1) else {
            return .unsupported(
                reason: "klib '\(uniqueName)' carries no v1 IR signatures (ir_signature_versions=\(properties["ir_signature_versions"] ?? ""))"
            )
        }
        return .supported
    }
}
