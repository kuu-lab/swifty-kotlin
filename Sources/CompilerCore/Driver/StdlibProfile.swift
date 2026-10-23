import Foundation

/// Selects which bundled stdlib sources make up a stdlib artifact (KUU-3016).
///
/// `full` is every bundled source (the historical behavior). `minimal`
/// leaves out the packages a program only reaches through an explicit
/// `import` that is outside the compiler's default-import set, so the
/// artifact — and therefore the import-side index the compiler decodes and
/// builds lookup maps over — is substantially smaller.
///
/// A minimal artifact never falls back to the full one on its own: a symbol
/// that lives in an excluded package is reported as an explicit
/// `KSWIFTK-LIB-0036` diagnostic that names the profile switch.
public enum StdlibProfile: String, CaseIterable, Sendable {
    case full
    case minimal

    /// Package prefixes excluded from the minimal profile. A prefix covers
    /// the package itself and every nested package.
    ///
    /// Everything in the compiler's default-import set
    /// (`makeDefaultImportPackages`) and every package a kept source
    /// depends on stays in — e.g. `kotlinx.io` (behind `kotlin.io` file
    /// streams), `kotlinx.cinterop` and `platform.*` (`kotlinx.io` Apple sources),
    /// `kotlin.concurrent` (atomics behind coroutines and `kotlin.native.concurrent`),
    /// `kotlin.experimental` (`@OptIn` on collection sources), `kotlin.io.encoding`
    /// (`kotlinx.io.bytestring`), `kotlin.js` and `java.nio`/`java.math`.
    /// When a kept source starts depending on one of these packages the
    /// stdlib-only build fails, which is the signal to move the prefix out of
    /// this list.
    static let minimalExcludedPackagePrefixes: [String] = [
        "kotlinx.coroutines",
        "kotlinx.serialization",
        "kotlinx.atomicfu",
        "kswiftk.atomicfu",
        "kotlin.test",
        "kotlin.uuid",
        "kotlin.io.path",
        "java.sql",
        "java.net",
        "java.security",
        "java.text",
    ]

    /// File name of the default-resolved artifact for this profile.
    public var artifactFileName: String {
        switch self {
        case .full: "KSwiftKStdlib.kklib"
        case .minimal: "KSwiftKStdlibMinimal.kklib"
        }
    }

    /// Whether a source declaring `package` belongs to this profile.
    public func includes(package: String) -> Bool {
        switch self {
        case .full:
            return true
        case .minimal:
            return !Self.isExcludedFromMinimal(package: package)
        }
    }

    /// Whether `package` (a dotted name) is covered by an excluded prefix.
    public static func isExcludedFromMinimal(package: String) -> Bool {
        for prefix in minimalExcludedPackagePrefixes
            where package == prefix || package.hasPrefix(prefix + ".")
        {
            return true
        }
        return false
    }

    /// Extracts the `package` declaration from a Kotlin source without
    /// lexing it: the first line that starts with `package `.
    static func declaredPackage(in contents: Data) -> String {
        guard let text = String(data: contents, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.hasPrefix("package ") else { continue }
            return line.dropFirst("package ".count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        }
        return ""
    }
}
