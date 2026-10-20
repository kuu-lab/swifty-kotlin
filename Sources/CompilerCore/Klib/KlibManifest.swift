import Foundation

/// Kotlin writes `manifest` with `java.util.Properties.store`: one
/// `key=value` (or `key: value`) per line, `#`/`!` comment lines, `\`
/// line continuations, and `\t \n \r \f \\ \uXXXX` escapes. Duplicate keys
/// keep the last value, matching `Properties.load` semantics.
package enum JavaProperties {
    package static func parse(_ text: String) throws -> [(key: String, value: String)] {
        var pairs: [(String, String)] = []
        var logical = ""
        var continuation = false

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for physicalLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
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
            pairs.append(try splitProperty(logical))
        }
        if continuation && !logical.isEmpty {
            pairs.append(try splitProperty(logical))
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

    private static func splitProperty(_ line: String) throws -> (key: String, value: String) {
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
        while valueStart < line.endIndex, isWhitespace(line[valueStart]) {
            valueStart = line.index(after: valueStart)
        }
        if valueStart < line.endIndex, line[valueStart] == "=" || line[valueStart] == ":" {
            valueStart = line.index(after: valueStart)
        }
        while valueStart < line.endIndex, isWhitespace(line[valueStart]) {
            valueStart = line.index(after: valueStart)
        }
        return try (unescape(String(line[..<keyEnd])), unescape(String(line[valueStart...])))
    }

    private static func isWhitespace(_ ch: Character) -> Bool {
        ch == " " || ch == "\t" || ch == "\u{0C}"
    }

    private static func unescape(_ string: String) throws -> String {
        guard string.contains("\\") else { return string }
        // Java escapes encode UTF-16 code units, including surrogate pairs.
        var result: [UInt16] = []
        var i = string.startIndex
        while i < string.endIndex {
            let ch = string[i]
            guard ch == "\\", string.index(after: i) < string.endIndex else {
                result.append(contentsOf: String(ch).utf16)
                i = string.index(after: i)
                continue
            }
            i = string.index(after: i)
            let esc = string[i]
            i = string.index(after: i)
            switch esc {
            case "t": result.append(9)
            case "n": result.append(10)
            case "r": result.append(13)
            case "f": result.append(12)
            case "u":
                var code = 0
                for _ in 0 ..< 4 {
                    guard i < string.endIndex, string[i].isASCII,
                          let digit = string[i].hexDigitValue else {
                        throw KlibFormatError.invalidManifest("malformed Unicode escape")
                    }
                    code = code * 16 + digit
                    i = string.index(after: i)
                }
                result.append(UInt16(code))
            default:
                result.append(contentsOf: String(esc).utf16)
            }
        }
        return String(decoding: result, as: UTF16.self)
    }
}

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

        package init?(_ string: String, allowsSuffix: Bool = false) {
            let parts = string.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard (2 ... 3).contains(parts.count),
                  Self.isDecimal(parts[0]), Self.isDecimal(parts[1]),
                  let major = Int(parts[0]),
                  let minor = Int(parts[1])
            else { return nil }
            // Kotlin may suffix versions ("2.4.20-dev-7885"); keep the
            // leading numeric component of the patch field.
            let patchField = parts.count > 2 ? parts[2] : "0"
            let digits = patchField.prefix(while: { $0.isASCII && $0.isNumber })
            let suffix = patchField.dropFirst(digits.count)
            guard !digits.isEmpty, let patch = Int(digits),
                  suffix.isEmpty || (allowsSuffix && (suffix.first == "-" || suffix.first == "+")) else {
                return nil
            }
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        private static func isDecimal(_ string: String) -> Bool {
            !string.isEmpty && string.allSatisfy { $0.isASCII && $0.isNumber }
        }

        package static func < (lhs: Version, rhs: Version) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }

        package var description: String { "\(major).\(minor).\(patch)" }
    }

    package enum Compatibility: Equatable {
        /// Uses an IR wire format supported by this reader.
        case supported
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
        self.compilerVersion = props["compiler_version"].flatMap { Version($0, allowsSuffix: true) }
        self.abiVersion = props["abi_version"].flatMap { Version($0) }
        self.metadataVersion = props["metadata_version"].flatMap { Version($0) }
        self.libraryVersion = props["library_version"]
        self.builtinsPlatform = props["builtins_platform"]
        self.irSignatureVersions = Set(
            (props["ir_signature_versions"] ?? "1")
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .compactMap { Int($0) }
        )
        self.depends = (props["depends"] ?? "")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
    }

    /// Kotlin 2.4.21 writes ABI 2.4.0. Compiler release versions and the IR
    /// ABI are independent: accepting an unimplemented future ABI would
    /// silently misread its declarations. The reader also retains ABI 2.3.
    package var compatibility: Compatibility {
        guard let abiVersion else {
            return .unsupported(reason: properties["abi_version"] == nil
                ? "manifest is missing 'abi_version'"
                : "manifest has invalid 'abi_version': \(properties["abi_version"] ?? "")")
        }
        guard abiVersion >= Version("2.3.0")!, abiVersion <= Version("2.4.0")! else {
            return .unsupported(
                reason: "klib '\(uniqueName)' has unsupported abi_version \(abiVersion) (supported: 2.3.0 through 2.4.0)"
            )
        }
        let signatureTokens = (properties["ir_signature_versions"] ?? "1")
            .split(whereSeparator: { $0 == "," || $0 == " " })
        guard !signatureTokens.isEmpty,
              signatureTokens.allSatisfy({ token in
                  !token.isEmpty && token.allSatisfy { $0.isASCII && $0.isNumber } && Int(token) != nil
              }), !irSignatureVersions.isDisjoint(with: [1, 2]) else {
            return .unsupported(
                reason: "klib '\(uniqueName)' has no supported IR signature version (supported: 1,2; ir_signature_versions=\(properties["ir_signature_versions"] ?? ""))"
            )
        }
        return .supported
    }
}
