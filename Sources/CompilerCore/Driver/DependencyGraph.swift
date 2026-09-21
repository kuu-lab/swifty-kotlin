import Foundation

/// Tracks symbol-level dependencies between source files for incremental compilation.
///
/// Each file *provides* (defines) a set of symbol names and *depends on* (references)
/// a set of symbol names.  When a file changes, every other file that depends on any
/// symbol provided by the changed file is added to the recompilation set.
public final class DependencyGraph: Codable {
    // MARK: - Storage

    private var providedSymbols: [String: Set<String>] = [:]

    private var dependedSymbols: [String: Set<String>] = [:]

    /// Package names are retained for source files so wildcard imports can be
    /// invalidated without treating every package as a dependency.
    private var providedPackages: [String: String] = [:]

    /// Package names imported with `*`, keyed by importing file.
    private var wildcardImportedPackages: [String: Set<String>] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case providedSymbols
        case dependedSymbols
        case providedPackages
        case wildcardImportedPackages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providedSymbols = try container.decodeIfPresent([String: Set<String>].self, forKey: .providedSymbols) ?? [:]
        dependedSymbols = try container.decodeIfPresent([String: Set<String>].self, forKey: .dependedSymbols) ?? [:]
        providedPackages = try container.decodeIfPresent([String: String].self, forKey: .providedPackages) ?? [:]
        wildcardImportedPackages = try container.decodeIfPresent([String: Set<String>].self, forKey: .wildcardImportedPackages) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providedSymbols, forKey: .providedSymbols)
        try container.encode(dependedSymbols, forKey: .dependedSymbols)
        try container.encode(providedPackages, forKey: .providedPackages)
        try container.encode(wildcardImportedPackages, forKey: .wildcardImportedPackages)
    }

    // MARK: - Mutation

    public func recordProvided(filePath: String, symbols: Set<String>) {
        providedSymbols[filePath] = symbols
    }

    /// Records the symbols and package provided by a source file.
    public func recordProvided(filePath: String, symbols: Set<String>, package: String) {
        recordProvided(filePath: filePath, symbols: symbols)
        providedPackages[filePath] = package
    }

    public func recordDepended(filePath: String, symbols: Set<String>) {
        dependedSymbols[filePath] = symbols
    }

    /// Records a package wildcard import such as `import example.api.*`.
    public func recordWildcardImport(filePath: String, package: String) {
        wildcardImportedPackages[filePath, default: []].insert(package)
    }

    // MARK: - Query

    /// Given a set of files that changed, compute the full set of files that need
    /// recompilation.  This includes:
    /// 1. The changed files themselves.
    /// 2. Any file that depends on a symbol provided by a changed file (transitively).
    ///
    /// The result is deterministic (sorted).
    public func recompilationSet(changedFiles: Set<String>, allFiles: [String]) -> [String] {
        if changedFiles.isEmpty {
            return []
        }

        var invalidatedSymbols = Set<String>()
        var invalidatedPackages = Set<String>()
        for changed in changedFiles {
            if let provided = providedSymbols[changed] {
                invalidatedSymbols.formUnion(provided)
            }
            if let package = providedPackages[changed] {
                invalidatedPackages.insert(package)
            }
        }

        var affected = changedFiles
        var frontier = changedFiles
        var visited = changedFiles

        // Iterate to handle transitive dependencies: if file A depends on file B's
        // symbol and file B is newly added to the recompilation set, file A's
        // provided symbols may also need to invalidate further files.
        while !frontier.isEmpty {
            var nextFrontier = Set<String>()
            for filePath in allFiles {
                guard !visited.contains(filePath) else { continue }
                let dependsOnChangedSymbol = if let depended = dependedSymbols[filePath] {
                    !depended.isDisjoint(with: invalidatedSymbols)
                } else {
                    false
                }
                let dependsOnChangedWildcard = wildcardImportedPackages[filePath]?.contains { package in
                    package.isEmpty || invalidatedPackages.contains(package)
                } ?? false
                if dependsOnChangedSymbol || dependsOnChangedWildcard {
                    affected.insert(filePath)
                    nextFrontier.insert(filePath)
                    // The newly-affected file's provided symbols may cause
                    // further invalidation.
                    if let provided = providedSymbols[filePath] {
                        invalidatedSymbols.formUnion(provided)
                    }
                    if let package = providedPackages[filePath] {
                        invalidatedPackages.insert(package)
                    }
                }
            }
            visited.formUnion(nextFrontier)
            frontier = nextFrontier
        }

        return allFiles.filter { affected.contains($0) }
    }

    public var trackedFiles: [String] {
        let allKeys = Set(providedSymbols.keys)
            .union(dependedSymbols.keys)
            .union(wildcardImportedPackages.keys)
        return allKeys.sorted()
    }

    public func provided(by filePath: String) -> Set<String> {
        providedSymbols[filePath] ?? []
    }

    public func depended(by filePath: String) -> Set<String> {
        dependedSymbols[filePath] ?? []
    }

    public func wildcardImportedPackages(by filePath: String) -> Set<String> {
        wildcardImportedPackages[filePath] ?? []
    }

    // MARK: - Serialization

    public func serialize() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public static func deserialize(from data: Data) throws -> DependencyGraph {
        let decoder = JSONDecoder()
        return try decoder.decode(DependencyGraph.self, from: data)
    }
}
