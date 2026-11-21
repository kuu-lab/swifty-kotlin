import Foundation

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
    /// (`kotlinx.io.bytestring`), `kotlin.js`, `java.net` (`java.nio.file.Path`),
    /// `java.nio`/`java.math`, `kotlin.uuid` (`java.util.UUID`),
    /// `java.security` (`java.util.UUID.nameUUIDFromBytes` digests through
    /// `MessageDigest`), and `kotlinx.atomicfu.locks` (the retained
    /// `java.util.concurrent` implementations).
    /// When a kept source starts depending on an excluded package the
    /// stdlib-only build fails, which is the signal to update the exclusion
    /// rule so that dependency remains in the profile.
    /// An exact-package exclusion keeps required child packages visible.
    static let minimalExcludedExactPackages: Set<String> = [
        "kotlinx.atomicfu",
    ]

    static let minimalExcludedPackagePrefixes: [String] = [
        "kotlinx.coroutines",
        "kotlinx.serialization",
        "kswiftk.atomicfu",
        "kotlin.test",
        "kotlin.io.path",
        "java.sql",
        "java.text",
    ]

    public var artifactFileName: String {
        switch self {
        case .full: "KSwiftKStdlib.kklib"
        case .minimal: "KSwiftKStdlibMinimal.kklib"
        }
    }

    public func includes(package: String) -> Bool {
        switch self {
        case .full:
            return true
        case .minimal:
            return !Self.isExcludedFromMinimal(package: package)
        }
    }

    public static func isExcludedFromMinimal(package: String) -> Bool {
        if minimalExcludedExactPackages.contains(package) {
            return true
        }
        for prefix in minimalExcludedPackagePrefixes
            where package == prefix || package.hasPrefix(prefix + ".")
        {
            return true
        }
        return false
    }

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
