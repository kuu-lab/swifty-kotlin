import Foundation

/// `group:artifact` identity of a Maven module, independent of version.
package struct MavenModuleID: Hashable, Comparable, Sendable, CustomStringConvertible {
    package let group: String
    package let artifact: String

    package init(group: String, artifact: String) {
        self.group = group
        self.artifact = artifact
    }

    package var description: String { "\(group):\(artifact)" }

    package static func < (lhs: Self, rhs: Self) -> Bool { lhs.description < rhs.description }
}

/// `group:artifact:version` as given to `--android-dependency`.
package struct MavenCoordinate: Hashable, Sendable, CustomStringConvertible {
    package let module: MavenModuleID
    package let version: String

    package init(module: MavenModuleID, version: String) {
        self.module = module
        self.version = version
    }

    package init?(parsing text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") }) else { return nil }
        self.init(module: MavenModuleID(group: parts[0], artifact: parts[1]), version: parts[2])
    }

    package var description: String { "\(module):\(version)" }

    /// Repository-relative directory: `androidx/core/core/1.13.1`.
    package var directory: String {
        module.group.replacingOccurrences(of: ".", with: "/") + "/\(module.artifact)/\(version)"
    }

    package func fileName(_ suffix: String) -> String { "\(module.artifact)-\(version)\(suffix)" }
}

/// Version ordering used for conflict resolution. It follows Gradle's
/// rules (the resolver Android builds use) rather than Maven's: parts split
/// at `.`, `-`, `_`, `+` and digit/letter boundaries; numeric parts compare
/// numerically and rank above words; `dev` < other words < `rc` <
/// `snapshot` < `final` < `ga` < `release` < `sp`. A trailing word makes a
/// version older (`1.0-alpha01` < `1.0`), a trailing number newer.
package enum MavenVersion {
    package static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(lhs), right = parts(rhs)
        for index in 0..<min(left.count, right.count) {
            let result = compare(part: left[index], right[index])
            if result != .orderedSame { return result }
        }
        if left.count == right.count { return .orderedSame }
        let longerIsLeft = left.count > right.count
        let extra = longerIsLeft ? left[right.count] : right[left.count]
        let longerWins = Int(extra) != nil
        return longerIsLeft == longerWins ? .orderedDescending : .orderedAscending
    }

    package static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedDescending
    }

    private static func parts(_ version: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var currentIsDigit: Bool?
        for character in version {
            if ".-_+".contains(character) {
                if !current.isEmpty { parts.append(current) }
                current = ""
                currentIsDigit = nil
                continue
            }
            let isDigit = character.isASCII && character.isNumber
            if let previous = currentIsDigit, previous != isDigit, !current.isEmpty {
                parts.append(current)
                current = ""
            }
            current.append(character)
            currentIsDigit = isDigit
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    private static func compare(part lhs: String, _ rhs: String) -> ComparisonResult {
        switch (Int(lhs), Int(rhs)) {
        case let (left?, right?):
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case (.some, nil): return .orderedDescending
        case (nil, .some): return .orderedAscending
        case (nil, nil):
            let left = rank(lhs), right = rank(rhs)
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
            let l = lhs.lowercased(), r = rhs.lowercased()
            return l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
        }
    }

    private static func rank(_ word: String) -> Int {
        switch word.lowercased() {
        case "dev": 0
        case "rc": 2
        case "snapshot": 3
        case "final": 4
        case "ga": 5
        case "release": 6
        case "sp": 7
        default: 1
        }
    }
}
