import Foundation

/// One early-predeclare target: source files whose top-level nominals must own
/// their symbols before synthetic stub registration builds signatures that
/// name them (the normal `collectAllHeaders` pass reaches them too late).
///
/// Rows run in `early` order and each row sweeps `ast.sortedFiles` in order, so
/// the table fixes SymbolID assignment order. Reordering rows, or folding two
/// rows into one sweep, shifts every later `$N` in the Sema goldens.
struct BundledPredeclareRow {
    /// Which declaration kinds count as the target. Set/Map use
    /// `.classOrInterface`: `.any` would define the typealiases of
    /// `CollectionAliases.kt` ahead of their turn.
    enum DeclKind { case classOnly, interfaceOnly, classOrInterface, any }

    var packageFQName: [String] = []
    var kind: DeclKind = .any
    var names: [String] = []
    var paths: [String] = []
    var basenameNominals: [String: String] = [:]
    var bundledStdlibOnly = false
    var skipFileIfDefined: [String] = []
    /// Skips the whole sweep when this FQ name is already owned. Looked up once,
    /// before the sweep. `SymbolTable.lookup` drains lazily imported entries and
    /// so allocates SymbolIDs: which of the two lookups a row uses, and when, is
    /// observable and must match the former per-nominal functions.
    var skipSweepIfDefined: [String] = []
    var shells: [String] = []
    var firstShellTypeParameter: String?

    func nominalName(of decl: Decl) -> InternedString? {
        switch decl {
        case let .classDecl(decl): kind == .interfaceOnly ? nil : decl.name
        case let .interfaceDecl(decl): kind == .classOnly ? nil : decl.name
        case let .objectDecl(decl): kind == .any ? decl.name : nil
        case let .typeAliasDecl(decl): kind == .any ? decl.name : nil
        case .funDecl, .propertyDecl, .enumEntryDecl: nil
        }
    }
}

extension BundledPredeclareRow {
    /// Order is the former `predeclareBundled*` call order and is load-bearing.
    static let early: [BundledPredeclareRow] = [
        // KSP-706: list/map/sequence `zip`/`partition`/`unzip` stubs build `Pair<...>`
        // return types before `collectAllHeaders` reaches `Tuples.kt`.
        .init(packageFQName: ["kotlin"], kind: .classOnly, names: ["Pair", "Triple"], shells: ["Pair", "Triple"]),
        .init(
            packageFQName: ["kotlin", "collections"], kind: .classOrInterface,
            basenameNominals: [
                "Set.kt": "Set", "MutableSet.kt": "MutableSet",
                "HashSet.kt": "HashSet", "LinkedHashSet.kt": "LinkedHashSet",
            ],
            bundledStdlibOnly: true
        ),
        .init(
            packageFQName: ["kotlin", "collections"], kind: .classOrInterface,
            basenameNominals: ["Map.kt": "Map", "MutableMap.kt": "MutableMap"],
            bundledStdlibOnly: true
        ),
        .init(
            packageFQName: ["kotlin"], kind: .interfaceOnly, names: ["Comparator"],
            paths: ["__bundled_kotlin/Comparator.kt"], bundledStdlibOnly: true,
            skipFileIfDefined: ["kotlin", "Comparator"]
        ),
        .init(
            packageFQName: ["kotlin"], paths: ["__bundled_kotlin/ArrayIntrinsics.kt"],
            bundledStdlibOnly: true, skipFileIfDefined: ["kotlin", "Array"],
            shells: [
                "Array", "BooleanArray", "ByteArray", "CharArray", "DoubleArray", "FloatArray", "IntArray",
                "LongArray", "ShortArray", "UByteArray", "UShortArray", "UIntArray", "ULongArray",
            ],
            firstShellTypeParameter: "T"
        ),
        .init(
            paths: ["__bundled_java/nio/charset/Charset.kt", "__bundled_kotlin/text/StringEncoding.kt"],
            skipSweepIfDefined: ["java", "nio", "charset", "Charset"]
        ),
        .init(paths: ["__bundled_java/util/Locale.kt"], skipSweepIfDefined: ["java", "util", "Locale"]),
        .init(packageFQName: ["kotlin", "random"], names: ["Random"]),
        .init(packageFQName: ["java", "util"], names: ["Random"]),
        .init(packageFQName: ["kotlin", "native"], names: ["OsFamily"]),
        .init(packageFQName: ["kotlin", "native", "runtime"], names: ["MemoryUsage"]),
        .init(packageFQName: ["kotlin", "native"], names: ["CpuArchitecture"]),
        .init(
            packageFQName: ["kotlin", "annotation"],
            names: ["AnnotationRetention", "AnnotationTarget", "MustBeDocumented", "Repeatable", "Retention", "Target"]
        ),
        // KSP-1472: claim the real annotation first so the opt-in bootstrap augments it
        // instead of creating a second class with the same FQName.
        .init(
            packageFQName: ["kotlin", "time"], names: ["ExperimentalTime"],
            paths: ["__bundled_kotlin/time/ExperimentalTime.kt"], bundledStdlibOnly: true
        ),
        .init(packageFQName: ["kotlin", "reflect"], names: ["KVariance"]),
        .init(packageFQName: ["kotlin", "reflect"], names: ["KTypeProjection"]),
        // KSP-1323: annotation classes cannot claim synthetic shells, so AssociatedObjectKey must be
        // predeclared; the marker interfaces take the same path for a single owner.
        .init(
            packageFQName: ["kotlin", "reflect"],
            names: [
                "AssociatedObjectKey", "KAnnotatedElement", "KClassifier", "KDeclarationContainer", "KFunction",
                "KMutableProperty", "KParameter", "KProperty", "KTypeParameter",
            ]
        ),
        .init(
            packageFQName: ["kotlin", "coroutines", "cancellation"], kind: .classOnly,
            names: ["CancellationException"]
        ),
        .init(packageFQName: ["kotlin", "native", "runtime"], names: ["GCInfo"]),
        .init(packageFQName: ["kotlin", "native", "runtime"], names: ["RootSetStatistics"]),
    ]
}

extension DataFlowSemaPhase {
    func predeclareNominalTypeHeaders(
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        scope: Scope,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        for declID in file.topLevelDecls {
            guard predeclared[declID] == nil else { continue }
            guard let decl = ast.arena.decl(declID) else { continue }
            switch decl {
            case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                break
            case .funDecl, .propertyDecl, .enumEntryDecl:
                continue
            }
            guard let declaration = topLevelDeclarationDescriptor(for: decl) else {
                continue
            }
            predeclared[declID] = defineTopLevelSymbol(
                declaration: declaration,
                decl: decl,
                file: file,
                symbols: symbols,
                scope: scope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner
            )
        }
    }

    func predeclareBundledEarlyHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        func intern(_ names: [String]) -> [InternedString] {
            names.map { interner.intern($0) }
        }
        for row in BundledPredeclareRow.early {
            let packageFQName = intern(row.packageFQName)
            let rowTargets = Set(intern(row.names))
            let skipFileFQName = intern(row.skipFileIfDefined)
            let ownedBeforeSweep = !row.skipSweepIfDefined.isEmpty
                && symbols.lookup(fqName: intern(row.skipSweepIfDefined)) != nil
            for file in ast.sortedFiles where !ownedBeforeSweep {
                guard packageFQName.isEmpty || file.packageFQName == packageFQName,
                      !row.bundledStdlibOnly || sourceManager.origin(of: file.fileID)?.isBundledStdlib == true
                else { continue }
                var targets = rowTargets
                var ownerFQName = skipFileFQName
                if !row.paths.isEmpty || !row.basenameNominals.isEmpty {
                    let path = sourceManager.path(of: file.fileID)
                    guard row.paths.isEmpty || row.paths.contains(path) else { continue }
                    if !row.basenameNominals.isEmpty {
                        let basename = path.split(separator: "/").last.map(String.init) ?? ""
                        guard let nominal = row.basenameNominals[basename] else { continue }
                        let nominalName = interner.intern(nominal)
                        targets = [nominalName]
                        ownerFQName = packageFQName + [nominalName]
                    }
                }
                guard let fileScope = fileScopes[file.fileID.rawValue],
                      targets.isEmpty || file.topLevelDecls.contains(where: { declID in
                          guard let decl = ast.arena.decl(declID), let name = row.nominalName(of: decl) else {
                              return false
                          }
                          return targets.contains(name)
                      })
                else { continue }
                if !ownerFQName.isEmpty, symbols.lookup(fqName: ownerFQName) != nil {
                    continue
                }
                predeclareNominalTypeHeaders(
                    file: file, ast: ast, symbols: symbols, scope: fileScope,
                    sourceManager: sourceManager, diagnostics: diagnostics,
                    interner: interner, into: &predeclared
                )
            }
            for (index, name) in row.shells.enumerated() {
                let shellName = interner.intern(name)
                let fqName = packageFQName + [shellName]
                let shell = symbols.lookup(fqName: fqName) ?? symbols.define(
                    kind: .class, name: shellName, fqName: fqName,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                guard index == 0, let typeParameter = row.firstShellTypeParameter,
                      types.nominalTypeParameterSymbols(for: shell).isEmpty
                else { continue }
                let parameterName = interner.intern(typeParameter)
                let parameterFQName = fqName + [parameterName]
                let parameterSymbol = symbols.lookup(fqName: parameterFQName) ?? symbols.define(
                    kind: .typeParameter, name: parameterName, fqName: parameterFQName,
                    declSite: nil, visibility: .private, flags: []
                )
                types.setNominalTypeParameterSymbols([parameterSymbol], for: shell)
                types.setNominalTypeParameterVariances([.invariant], for: shell)
            }
        }
    }
}
