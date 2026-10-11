import Foundation

extension DataFlowSemaPhase {
    /// BUG-143: Registers the symbols of top-level nominal type declarations
    /// (class/interface/object/typealias) before any signature type annotation is
    /// resolved, so declarations can reference types declared further down in the
    /// same file. Returns the pre-registered symbols keyed by declaration so that
    /// `collectHeader` reuses them instead of defining a second symbol.
    ///
    /// Idempotent per `declID`: a declaration already present in `predeclared`
    /// (e.g. from `predeclareBundledTupleHeaders`'s earlier, narrower pass) is
    /// left untouched rather than defined a second time.
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
            guard let declaration = topLevelDeclarationDescriptor(for: decl, diagnostics: nil) else {
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

    /// KSP-706: forward-declares `kotlin.Pair`/`kotlin.Triple` from their bundled
    /// `Tuples.kt` source before early synthetic stub registration runs. Several
    /// stub registrations (list/map/sequence `zip`/`partition`/`unzip`, ...)
    /// build `Pair<...>` return types and look the class up by name well before
    /// `collectAllHeaders` visits `Tuples.kt` in the normal pass. Running this
    /// narrow slice of `predeclareNominalTypeHeaders` first gives them the real
    /// class symbol directly, instead of routing through a throwaway synthetic
    /// placeholder that `collectHeader` swaps out later.
    ///
    /// Configurations with neither bundled stdlib source nor a merged library
    /// import (e.g. `--no-stdlib`) never get a real declaration for `Pair`/
    /// `Triple` at all, so a bare synthetic shell is defined as a fallback for
    /// whichever of the two names is still unresolved afterward -- matching
    /// what the deleted `HeaderHelpers+SyntheticPairTripleAnchors.swift` did
    /// unconditionally, but only as a last resort now.
    func predeclareBundledTupleHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let pairName = interner.intern("Pair")
        let tripleName = interner.intern("Triple")
        let kotlinPkg = [interner.intern("kotlin")]
        for file in ast.sortedFiles where file.packageFQName == kotlinPkg {
            let declaresTupleClass = file.topLevelDecls.contains { declID in
                guard case let .classDecl(classDecl)? = ast.arena.decl(declID) else { return false }
                return classDecl.name == pairName || classDecl.name == tripleName
            }
            guard declaresTupleClass, let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
        // When no bundled declaration was predeclared above (--no-stdlib, or an
        // imported artifact already supplies the symbol), fall back to a bare
        // synthetic class shell so `Pair`/`Triple` still resolve as class types.
        for name in [pairName, tripleName] {
            let fqName = kotlinPkg + [name]
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .class,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
    }

    /// KSP-704: make the source-backed set nominals available before collection
    /// residuals register their Sequence/Iterable/Array overloads. The normal
    /// header pass later fills these symbols with the complete Kotlin source
    /// declarations.
    func predeclareBundledSetHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let kotlinCollectionsPackage = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        let bundledSetFileNominals = [
            "Set.kt": "Set",
            "MutableSet.kt": "MutableSet",
            "HashSet.kt": "HashSet",
            "LinkedHashSet.kt": "LinkedHashSet",
        ]

        for file in ast.sortedFiles where
            sourceManager.origin(of: file.fileID)?.isBundledStdlib == true
        {
            let basename = sourceManager.path(of: file.fileID)
                .split(separator: "/")
                .last
                .map(String.init) ?? ""
            guard let nominalName = bundledSetFileNominals[basename],
                  file.packageFQName == kotlinCollectionsPackage
            else {
                continue
            }
            guard let fileScope = fileScopes[file.fileID.rawValue] else {
                continue
            }
            let nominalSymbolName = interner.intern(nominalName)
            guard file.topLevelDecls.contains(where: { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case let .classDecl(classDecl):
                    return classDecl.name == nominalSymbolName
                case let .interfaceDecl(interfaceDecl):
                    return interfaceDecl.name == nominalSymbolName
                default:
                    return false
                }
            }), symbols.lookup(fqName: kotlinCollectionsPackage + [nominalSymbolName]) == nil
            else {
                // An imported stdlib artifact already owns this nominal.
                continue
            }
            predeclareNominalTypeHeaders(
                file: file,
                ast: ast,
                symbols: symbols,
                scope: fileScope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner,
                into: &predeclared
            )
        }
    }

    /// KSP-703: make the source-backed map nominals available before the
    /// collection residual registry runs. The normal header pass later fills
    /// these symbols with their complete Kotlin declarations.
    func predeclareBundledMapHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let kotlinCollectionsPackage = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        let bundledMapFileNominals = [
            "Map.kt": "Map",
            "MutableMap.kt": "MutableMap",
        ]

        for file in ast.sortedFiles where
            sourceManager.origin(of: file.fileID)?.isBundledStdlib == true
        {
            let basename = sourceManager.path(of: file.fileID)
                .split(separator: "/")
                .last
                .map(String.init) ?? ""
            guard let nominalName = bundledMapFileNominals[basename],
                  file.packageFQName == kotlinCollectionsPackage
            else {
                continue
            }
            guard let fileScope = fileScopes[file.fileID.rawValue] else {
                continue
            }
            let nominalSymbolName = interner.intern(nominalName)
            guard file.topLevelDecls.contains(where: { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case let .classDecl(classDecl):
                    return classDecl.name == nominalSymbolName
                case let .interfaceDecl(interfaceDecl):
                    return interfaceDecl.name == nominalSymbolName
                default:
                    return false
                }
            }), symbols.lookup(fqName: kotlinCollectionsPackage + [nominalSymbolName]) == nil
            else {
                continue
            }
            predeclareNominalTypeHeaders(
                file: file,
                ast: ast,
                symbols: symbols,
                scope: fileScope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner,
                into: &predeclared
            )
        }
    }

    /// KSP-1520: make the source-backed Comparator nominal available to early
    /// synthetic registrations without creating a duplicate declaration.
    func predeclareBundledComparatorHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let comparatorPath = "__bundled_kotlin/Comparator.kt"
        let kotlinPackage = [interner.intern("kotlin")]
        let comparatorName = interner.intern("Comparator")

        for file in ast.sortedFiles
            where sourceManager.origin(of: file.fileID)?.isBundledStdlib == true
                && sourceManager.path(of: file.fileID) == comparatorPath
                && file.packageFQName == kotlinPackage
        {
            guard file.topLevelDecls.contains(where: { declID in
                guard case let .interfaceDecl(interfaceDecl)? = ast.arena.decl(declID) else {
                    return false
                }
                return interfaceDecl.name == comparatorName
            }) else {
                continue
            }
            guard let fileScope = fileScopes[file.fileID.rawValue] else {
                continue
            }
            if symbols.lookup(fqName: kotlinPackage + [comparatorName]) != nil {
                // An imported stdlib artifact already owns the nominal. Do not
                // predeclare the bundled source over that imported layout.
                continue
            }
            predeclareNominalTypeHeaders(
                file: file,
                ast: ast,
                symbols: symbols,
                scope: fileScope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner,
                into: &predeclared
            )
        }
    }

    /// KSP-1517: `Array<T>` and the primitive array types (`BooleanArray`,
    /// `ByteArray`, ...) are source-backed nominal shells in
    /// `ArrayIntrinsics.kt`, but array-typed synthetic signatures (e.g.
    /// `MutableCollection<T>.addAll(array: Array<out T>)`) are registered
    /// before the normal bundled header collection pass. Predeclare those
    /// nominals so those signatures resolve without a synthetic array
    /// anchor.
    ///
    /// Configurations with neither bundled stdlib source nor a merged
    /// library import (e.g. `--no-stdlib`) never get a real declaration for
    /// these names at all, so a bare synthetic shell is defined as a
    /// fallback for whichever name is still unresolved afterward -- matching
    /// what the deleted `HeaderHelpers+SyntheticArrayStubs.swift` did
    /// unconditionally, but only as a last resort now.
    func predeclareBundledArrayHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let arrayIntrinsicsPath = "__bundled_kotlin/ArrayIntrinsics.kt"
        let kotlinPkg = [interner.intern("kotlin")]
        let arrayClassNames = [
            "Array", "BooleanArray", "ByteArray", "CharArray", "DoubleArray",
            "FloatArray", "IntArray", "LongArray", "ShortArray", "UByteArray",
            "UShortArray", "UIntArray", "ULongArray",
        ].map { interner.intern($0) }

        for file in ast.sortedFiles
            where sourceManager.origin(of: file.fileID)?.isBundledStdlib == true
                && sourceManager.path(of: file.fileID) == arrayIntrinsicsPath
                && file.packageFQName == kotlinPkg
        {
            guard let fileScope = fileScopes[file.fileID.rawValue] else {
                continue
            }
            if symbols.lookup(fqName: kotlinPkg + [arrayClassNames[0]]) != nil {
                // An imported stdlib artifact already owns the nominal. Do not
                // predeclare the bundled source over that imported layout.
                continue
            }
            predeclareNominalTypeHeaders(
                file: file,
                ast: ast,
                symbols: symbols,
                scope: fileScope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner,
                into: &predeclared
            )
        }
        let arrayFQName = kotlinPkg + [interner.intern("Array")]
        let arraySymbol: SymbolID = if let existing = symbols.lookup(fqName: arrayFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("Array"),
                fqName: arrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if types.nominalTypeParameterSymbols(for: arraySymbol).isEmpty {
            let tParamName = interner.intern("T")
            let tParamSymbol = symbols.lookup(fqName: arrayFQName + [tParamName]) ?? symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: arrayFQName + [tParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            types.setNominalTypeParameterSymbols([tParamSymbol], for: arraySymbol)
            types.setNominalTypeParameterVariances([.invariant], for: arraySymbol)
        }
        for name in arrayClassNames where name != arrayClassNames[0] {
            let fqName = kotlinPkg + [name]
            guard symbols.lookup(fqName: fqName) == nil else { continue }
            _ = symbols.define(
                kind: .class,
                name: name,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
    }

    /// KSP-711: forward-declares `Charset` and `Charsets` from
    /// `StringEncoding.kt` before synthetic FileIO bridges are registered.
    /// Their source symbols must be available while bridge signatures are
    /// constructed; `collectAllHeaders` later fills in the complete headers.
    func predeclareBundledStringEncodingHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let charsetFQName = [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Charset"),
        ]
        guard symbols.lookup(fqName: charsetFQName) == nil else { return }

        for file in ast.sortedFiles
            where sourceManager.path(of: file.fileID) == "__bundled_kotlin/text/StringEncoding.kt"
        {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-717: forward-declares `java.util.Locale` from `Locale.kt` before
    /// source-backed `String.Companion.format(locale, ...)` is collected. Its
    /// nominal symbol must be available while the extension signature is
    /// resolved; `collectAllHeaders` later fills in the complete header (the
    /// two bridged constructors).
    func predeclareBundledJavaUtilLocaleHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let localeFQName = [
            interner.intern("java"),
            interner.intern("util"),
            interner.intern("Locale"),
        ]
        guard symbols.lookup(fqName: localeFQName) == nil else { return }

        for file in ast.sortedFiles
            where sourceManager.path(of: file.fileID) == "__bundled_java/util/Locale.kt"
        {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-918: forward-declare the six `kotlin.annotation` core declarations
    /// before synthetic annotation bootstrap runs. Their source declarations
    /// refer to one another through `@Target`, `@Retention`, and
    /// `@MustBeDocumented`, so the symbols must exist before annotations are
    /// registered on the first source header.
    func predeclareBundledAnnotationHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("annotation")]
        let coreNames: Set<InternedString> = [
            interner.intern("AnnotationRetention"),
            interner.intern("AnnotationTarget"),
            interner.intern("MustBeDocumented"),
            interner.intern("Repeatable"),
            interner.intern("Retention"),
            interner.intern("Target"),
        ]

        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresCoreType = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case let .classDecl(classDecl):
                    return coreNames.contains(classDecl.name)
                case let .interfaceDecl(interfaceDecl):
                    return coreNames.contains(interfaceDecl.name)
                case let .objectDecl(objectDecl):
                    return coreNames.contains(objectDecl.name)
                case let .typeAliasDecl(typeAliasDecl):
                    return coreNames.contains(typeAliasDecl.name)
                default:
                    return false
                }
            }
            guard declaresCoreType, let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file,
                ast: ast,
                symbols: symbols,
                scope: fileScope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner,
                into: &predeclared
            )
        }
    }

    /// KSP-1472: forward-declare the source-backed `kotlin.time.ExperimentalTime`
    /// annotation before the experimental-time bootstrap attaches its residual
    /// constructor and opt-in metadata.
    func predeclareBundledExperimentalTimeHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("time")]
        let targetName = interner.intern("ExperimentalTime")
        for file in ast.sortedFiles
            where sourceManager.origin(of: file.fileID)?.isBundledStdlib == true
                && sourceManager.path(of: file.fileID) == "__bundled_kotlin/time/ExperimentalTime.kt"
                && file.packageFQName == packageFQName
        {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1522: forward-declares the source-backed `kotlin.random.Random` and
    /// `java.util.Random` nominal types before synthetic collection and Sequence
    /// members resolve their parameter types. `PlatformRandom.kt` can also be
    /// collected before `JavaUtilRandom.kt`, so both owners must be available in
    /// the same early pass.
    func predeclareBundledRandomHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let targets: [([InternedString], InternedString)] = [
            (
                [interner.intern("kotlin"), interner.intern("random")],
                interner.intern("Random")
            ),
            (
                [interner.intern("java"), interner.intern("util")],
                interner.intern("Random")
            ),
        ]
        for (packageFQName, targetName) in targets {
            for file in ast.sortedFiles where file.packageFQName == packageFQName {
                let declaresTargetNominal = file.topLevelDecls.contains { declID in
                    guard let decl = ast.arena.decl(declID) else { return false }
                    switch decl {
                    case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                        return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                    case .funDecl, .propertyDecl, .enumEntryDecl:
                        return false
                    }
                }
                guard declaresTargetNominal,
                      let fileScope = fileScopes[file.fileID.rawValue]
                else { continue }
                predeclareNominalTypeHeaders(
                    file: file, ast: ast, symbols: symbols, scope: fileScope,
                    sourceManager: sourceManager, diagnostics: diagnostics,
                    interner: interner, into: &predeclared
                )
            }
        }
    }

    /// KSP-1150: forward-declares the source-backed cancellation nominal before
    /// residual coroutine registration needs its type and constructor owner.
    func predeclareBundledCancellationExceptionHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
            interner.intern("cancellation"),
        ]
        let targetName = interner.intern("CancellationException")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard case let .classDecl(classDecl)? = ast.arena.decl(declID) else {
                    return false
                }
                return classDecl.name == targetName
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file,
                ast: ast,
                symbols: symbols,
                scope: fileScope,
                sourceManager: sourceManager,
                diagnostics: diagnostics,
                interner: interner,
                into: &predeclared
            )
        }
    }

    /// KSP-1210: forward-declares the source-backed Native OsFamily enum before
    /// Platform.osFamily's retained runtime bridge resolves its property type.
    func predeclareBundledOsFamilyHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("native")]
        let targetName = interner.intern("OsFamily")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTargetNominal = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTargetNominal,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1266: forward-declares the source-backed Native MemoryUsage class
    /// before GCInfo's residual synthetic properties resolve their value type.
    func predeclareBundledMemoryUsageHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [
            interner.intern("kotlin"),
            interner.intern("native"),
            interner.intern("runtime"),
        ]
        let targetName = interner.intern("MemoryUsage")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTargetNominal = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTargetNominal,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1198: forward-declares the source-backed Native CpuArchitecture
    /// enum before Platform.cpuArchitecture's retained runtime bridge resolves
    /// its property type.
    func predeclareBundledCpuArchitectureHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("native")]
        let targetName = interner.intern("CpuArchitecture")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTargetNominal = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTargetNominal,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1334: forward-declares the source-backed KTypeProjection nominal
    /// before reflection synthetic stubs resolve its property owner.
    func predeclareBundledKTypeProjectionHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("reflect")]
        let targetName = interner.intern("KTypeProjection")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1337: forward-declares the source-backed KVariance enum before
    /// reflection synthetic stubs construct signatures that reference it.
    func predeclareBundledKVarianceHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("reflect")]
        let targetName = interner.intern("KVariance")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1323: forward-declares the source-backed kotlin.reflect nominal
    /// types (AssociatedObjectKey and the marker interfaces) before the
    /// reflection synthetic stubs attach their residual members. Annotation
    /// classes cannot claim synthetic shells, so AssociatedObjectKey must be
    /// predeclared; the interfaces take the same path for a single owner.
    func predeclareBundledReflectTopLevelHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [interner.intern("kotlin"), interner.intern("reflect")]
        let targetNames: Set<InternedString> = [
            interner.intern("AssociatedObjectKey"),
            interner.intern("KAnnotatedElement"),
            interner.intern("KClassifier"),
            interner.intern("KDeclarationContainer"),
            interner.intern("KFunction"),
            interner.intern("KMutableProperty"),
            interner.intern("KParameter"),
            interner.intern("KProperty"),
            interner.intern("KTypeParameter"),
        ]
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    guard let name = topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name
                    else { return false }
                    return targetNames.contains(name)
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1264: forward-declares the source-backed Native GCInfo class
    /// before synthetic runtime properties are registered against its owner.
    func predeclareBundledGCInfoHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [
            interner.intern("kotlin"),
            interner.intern("native"),
            interner.intern("runtime"),
        ]
        let targetName = interner.intern("GCInfo")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTargetNominal = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTargetNominal,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }

    /// KSP-1269: forward-declares the source-backed RootSetStatistics nominal
    /// before the NativeRuntime residual stubs resolve its constructor and
    /// property owners.
    func predeclareBundledRootSetStatisticsHeaders(
        ast: ASTModule,
        fileScopes: [Int32: FileScope],
        symbols: SymbolTable,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        into predeclared: inout [DeclID: SymbolID]
    ) {
        let packageFQName = [
            interner.intern("kotlin"),
            interner.intern("native"),
            interner.intern("runtime"),
        ]
        let targetName = interner.intern("RootSetStatistics")
        for file in ast.sortedFiles where file.packageFQName == packageFQName {
            let declaresTarget = file.topLevelDecls.contains { declID in
                guard let decl = ast.arena.decl(declID) else { return false }
                switch decl {
                case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl:
                    return topLevelDeclarationDescriptor(for: decl, diagnostics: nil)?.name == targetName
                case .funDecl, .propertyDecl, .enumEntryDecl:
                    return false
                }
            }
            guard declaresTarget,
                  let fileScope = fileScopes[file.fileID.rawValue]
            else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: sourceManager, diagnostics: diagnostics,
                interner: interner, into: &predeclared
            )
        }
    }
}
