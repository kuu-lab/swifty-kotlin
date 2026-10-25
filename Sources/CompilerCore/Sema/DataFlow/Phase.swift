import Foundation
import Dispatch

final class DataFlowSemaPhase: CompilerPhase {
    static let name = "DataFlowSema"

    private let capturesImportedStdlibSnapshot: Bool

    func builtinTypeNames(interner: StringInterner) -> BuiltinTypeNames {
        BuiltinTypeNames(interner: interner)
    }

    init(capturingImportedStdlibSnapshot: Bool = false) {
        capturesImportedStdlibSnapshot = capturingImportedStdlibSnapshot
    }

    func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("No AST available for semantic analysis.")
        }

        let setupStart = ctx.phaseTimer.map { _ in DispatchTime.now().uptimeNanoseconds }

        let cachedImportSnapshot = KklibSemaSession.cachedSnapshot(options: ctx.options)
        let symbols = cachedImportSnapshot?.makeSymbols() ?? SymbolTable()
        let types = cachedImportSnapshot?.makeTypes(symbols: symbols) ?? TypeSystem()
        types.symbolTable = symbols
        let bindings = BindingTable()

        // Build the bundled declaration index from AST before synthetic registration,
        // but keep bundled SymbolTable header collection after synthetic type foundations.
        // Computed before SemaModule construction so it can be passed into the
        // initializer directly (see SemaModule.bundledIndex) rather than set
        // via a later mutation, matching the existing importedInlineFunctions
        // constructor-parameter convention.
        var bundledIndex = withSubPhaseTiming("buildBundledIndex", timer: ctx.phaseTimer) {
            BundledDeclarationIndex.build(
                ast: ast,
                symbols: symbols,
                types: types,
                sourceManager: ctx.sourceManager,
                interner: ctx.interner,
                includeUserSources: ctx.options.emit.isJVM && ctx.options.stdlibOnly
            )
        }
        let sema = SemaModule(
            symbols: symbols, types: types,
            bindings: bindings, diagnostics: ctx.diagnostics,
            interner: ctx.interner,
            nameBasedDestructuringMode: ctx.options.nameBasedDestructuringMode,
            bundledIndex: bundledIndex
        )

        sema.requiresResolvedLibraryCalls = ctx.options.emit.isJVM
        sema.stdlibProfile = ctx.options.stdlibProfile
        let fileScopesBeforeImports = KklibSemaSession.shouldCache(options: ctx.options)
            ? nil
            : buildFileScopes(ast: ast, symbols: symbols, interner: ctx.interner)
        let (importedInlineFunctions, importDeferredWork) = withSubPhaseTiming(
            cachedImportSnapshot == nil ? "loadImports" : "restoreImports",
            timer: ctx.phaseTimer
        ) {
            if let cachedImportSnapshot {
                for diagnostic in cachedImportSnapshot.importDiagnostics {
                    ctx.diagnostics.emit(diagnostic)
                }
                return cachedImportSnapshot.makeDeferredWork(
                    phase: self,
                    symbols: symbols,
                    types: types,
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner
                )
            }
            return loadImports(ctx: ctx, symbols: symbols, types: types)
        }
        let fileScopes = fileScopesBeforeImports
            ?? buildFileScopes(ast: ast, symbols: symbols, interner: ctx.interner)
        sema.importedInlineFunctions = importedInlineFunctions
        sema.klibModules = importDeferredWork.klibModules
        importDeferredWork.lazyLoaderState?.descriptorSink = { [weak sema] symbol, descriptor in
            sema?.importedInlineFunctions.register(descriptor, for: symbol)
        }
        sema.resolveDemandedImportedInlineBodies =
            importDeferredWork.lazyLoaderState?.resolveDemandedInlineBodies
        if capturesImportedStdlibSnapshot {
            symbols.materializeAllIndexedLibraryState()
            // The snapshot serialises descriptors only; pending bindings are
            // a runtime index concept that is not persisted. Register every
            // deferred inline body now so consumer compiles can still expand
            // calls to them.
            if let lazyState = importDeferredWork.lazyLoaderState {
                registerAllImportedInlineFunctionDescriptors(
                    state: lazyState,
                    symbols: symbols,
                    types: types,
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner
                )
            }
        }

        // When compiling against bundled stdlib source rather than a prebuilt
        // library artifact, forward-declare the source-backed nominals (`Pair`,
        // `Set`, `Array`, ...) now, before `registerSyntheticDelegateStubs` below
        // runs stub registrations that reference them in their signatures. When a
        // prebuilt library is used instead, `loadImports` above already defined
        // the real symbols, so these passes simply find nothing to do.
        var predeclaredEarlyHeaders: [DeclID: SymbolID] = [:]
        withSubPhaseTiming("predeclareBundledHeaders", timer: ctx.phaseTimer) {
            // JVM intrinsic nominals own their headers before residual
            // registration, just as source-backed Native stdlib types do.
            if ctx.options.emit.isJVM {
                for file in ast.sortedFiles where ctx.sourceManager.path(of: file.fileID).hasPrefix("<kswiftk-jvm>/") {
                    if let scope = fileScopes[file.fileID.rawValue] {
                        predeclareNominalTypeHeaders(file: file, ast: ast, symbols: symbols, scope: scope, sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics, interner: ctx.interner, into: &predeclaredEarlyHeaders)
                    }
                }
            }
            // Table-driven (`BundledPredeclareRow.early`): the row order fixes SymbolID assignment.
            predeclareBundledEarlyHeaders(
                ast: ast, fileScopes: fileScopes, symbols: symbols, types: types,
                sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
                interner: ctx.interner, into: &predeclaredEarlyHeaders
            )
        }
        withSubPhaseTiming("mergeImportedStdlibSymbolsIntoBundledIndex", timer: ctx.phaseTimer) {
            if let stdlibModuleName = importDeferredWork.stdlibModuleName {
                bundledIndex = mergeImportedStdlibSymbolsIntoBundledIndex(
                    bundledIndex: bundledIndex,
                    stdlibModuleName: stdlibModuleName,
                    stdlibIndexSource: importDeferredWork.lazyLoaderState?.stdlibIndexSource,
                    precomputedMemberIndex: importDeferredWork.lazyLoaderState?.stdlibMemberIndex,
                    stdlibMemberKeys: importDeferredWork.stdlibMemberKeys,
                    symbols: symbols,
                    types: types,
                    interner: ctx.interner
                )
                importDeferredWork.lazyLoaderState?.bundledIndex = bundledIndex
                // STDLIB-SHARED-002: SemaModule was created before imported symbols were
                // merged into the bundled index, so update it before any type-checker
                // queries rely on source-backed stdlib declarations.
                sema.bundledIndex = bundledIndex
            }
        }
        initializeSourceBackedCloseableTypes(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )

        // Anchor real JVM runtime nominals before optional synthetic fallbacks.
        if ctx.options.emit.isJVM && ctx.options.stdlibOnly {
            sema.isJVMStdlibBuild = true
            for file in ast.sortedFiles where ctx.sourceManager.origin(of: file.fileID) == .user {
                if let scope = fileScopes[file.fileID.rawValue] {
                    predeclareNominalTypeHeaders(file: file, ast: ast, symbols: symbols, scope: scope, sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics, interner: ctx.interner, into: &predeclaredEarlyHeaders)
                }
            }
        }
        withSubPhaseTiming("registerSyntheticDelegateStubs", timer: ctx.phaseTimer) {
            if importDeferredWork.stdlibHasPrecomputedSyntheticStubs,
               restorePrecomputedStdlibSyntheticTypeSymbols(
                   symbols: symbols,
                   types: types,
                   interner: ctx.interner
               )
            {
                // The artifact owns these records; the registry would rebuild
                // the same symbols and re-decode their lazy metadata here.
            } else {
                registerSyntheticDelegateStubs(
                    symbols: symbols,
                    types: types,
                    interner: ctx.interner,
                    bundledIndex: bundledIndex
                )
            }
        }
        // Apply imported class/interface layouts after synthetic bootstrap
        // registration and before bundled source headers are collected, so
        // imported vtable/itable slots can resolve against final symbols.
        withSubPhaseTiming("applyImportedLibraryDeferredWork", timer: ctx.phaseTimer) {
            withSubPhaseTiming("applyDeferredLayouts", timer: ctx.phaseTimer) {
                applyImportedLibraryDeferredWork(
                    importDeferredWork,
                    symbols: symbols,
                    types: types,
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner,
                    bundledIndex: bundledIndex
                )
            }
            withSubPhaseTiming("normalizeImportedMemberSignatures", timer: ctx.phaseTimer) {
                normalizeImportedLibraryMemberSignatures(
                    importDeferredWork,
                    symbols: symbols,
                    types: types,
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner
                )
            }
            withSubPhaseTiming("initializeSourceBackedCloseableTypes", timer: ctx.phaseTimer) {
                initializeSourceBackedCloseableTypes(
                    symbols: symbols,
                    types: types,
                    interner: ctx.interner
                )
            }
        }
        if capturesImportedStdlibSnapshot {
            sema.bundledIndex = bundledIndex
            ctx.storeSema(sema)
            return
        }
        // Keep overlap diagnostics as an explicit guard test helper. Emitting
        // them during normal Sema pollutes user diagnostics for unaffected code.
        // Enum header synthesis runs during bundled header collection rather
        // than synthetic stub registration, so expose the same bundled index
        // while headers are collected for source-backed enum API skip guards.
        let previousBundledIndex = BundledSyntheticStubRegistration.bundledIndex
        BundledSyntheticStubRegistration.bundledIndex = bundledIndex
        if let setupStart {
            ctx.phaseTimer?.recordSubPhase(
                "sema-setup", startTime: setupStart, endTime: DispatchTime.now().uptimeNanoseconds
            )
        }
        withSubPhaseTiming("collectAllHeaders", timer: ctx.phaseTimer) {
            collectAllHeaders(
                ast: ast, fileScopes: fileScopes,
                symbols: symbols, types: types, bindings: bindings, ctx: ctx,
                predeclared: predeclaredEarlyHeaders
            )
        }
        BundledSyntheticStubRegistration.bundledIndex = previousBundledIndex
        // Validate before normalization erases projections in function aliases.
        for alias in symbols.allSymbols() where alias.kind == .typeAlias
            && !alias.flags.contains(.importedLibrary)
        {
            guard alias.declSite != nil,
                  let underlying = symbols.typeAliasUnderlyingType(for: alias.id) else { continue }
            TypeProjectionValidator(symbols: symbols, types: types, interner: ctx.interner,
                                    diagnostics: ctx.diagnostics, range: alias.declSite)
                .validate(type: underlying)
        }
        normalizeNestedTypeAliasUnderlyingTypes(symbols: symbols, types: types)
        patchSourceBackedNativeUnhandledExceptionHookContract(
            symbols: symbols,
            interner: ctx.interner,
            bundledIndex: bundledIndex
        )
        // The residual MutableSet Array overload needs complete owner headers.
        // Iterable/Sequence addAll use the bundled MutableCollection extensions.
        let kotlinCollectionsPackage = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("collections"),
        ]
        registerMutableCollectionArrayAddAllMembers(
            symbols: symbols,
            types: types,
            interner: ctx.interner,
            kotlinCollectionsPkg: kotlinCollectionsPackage
        )
        // KSP-1332: the source declaration spells this as List<KTypeProjection>,
        // while the compiler's residual List model represents covariant uses
        // with an explicit out projection. Reapply that existing KType contract
        // after source collection has claimed the old synthetic anchor.
        patchKTypeArgumentsType(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        // KSP-1333: same covariant List contract for KTypeParameter.upperBounds.
        patchKTypeParameterUpperBoundsType(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        initializeSourceBackedCloseableTypes(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        types.functionInterfaceSymbol = symbols.lookupAll(
            fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Function")]
        ).first { symbols.symbol($0)?.kind == .interface }
        bundledIndex.warnSyntheticOverlaps(
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        assignCompilationModuleFQNames(
            symbols: symbols,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner
        )
        // KSP-499 Stage 3: keep the bundled declaration index reachable via
        // `sema.bundledIndex` for the rest of the compilation (body
        // type-checking, KIR lowering) — the transient
        // `BundledSyntheticStubRegistration` thread-local used above is
        // already cleared by `registerSyntheticDelegateStubs`'s own `defer`
        // once header registration finished.
        sema.bundledIndex = bundledIndex
        withSubPhaseTiming("runValidationPasses", timer: ctx.phaseTimer) {
            runValidationPasses(ast: ast, symbols: symbols, bindings: bindings, types: types, ctx: ctx, sema: sema)
        }
        patchSourceBackedPreconditionContractEffects(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        // ARCH-021: body type checking and later KIR lowering must use the
        // same exact compiler-owned SymbolIDs. Resolve after all headers and
        // validation-created symbols are present, but before body analysis.
        sema.wellKnownSymbols = WellKnownSymbols(
            symbols: symbols,
            interner: ctx.interner,
            sourceManager: ctx.sourceManager
        )
        withSubPhaseTiming("runBodyAnalysis", timer: ctx.phaseTimer) {
            runBodyAnalysis(ast: ast, symbols: symbols, types: types, bindings: bindings, ctx: ctx)
        }
        ctx.storeSema(sema)
    }

    func buildFileScopes(
        ast: ASTModule, symbols: SymbolTable, interner: StringInterner
    ) -> [Int32: FileScope] {
        let rootScope = PackageScope(parent: nil, symbols: symbols)
        var fileScopes: [Int32: FileScope] = [:]
        for file in ast.sortedFiles {
            let packageSymbol = definePackageSymbol(for: file, symbols: symbols, interner: interner)
            let packageScope = PackageScope(parent: rootScope, symbols: symbols)
            packageScope.insert(packageSymbol)
            fileScopes[file.fileID.rawValue] = FileScope(parent: packageScope, symbols: symbols)
        }
        return fileScopes
    }

    private func loadImports(
        ctx: CompilationContext, symbols: SymbolTable, types: TypeSystem
    ) -> (ImportedInlineFunctionStore, LibraryImportDeferredWork) {
        let diagnosticStart = ctx.diagnostics.diagnostics.count
        let importedInlineFunctions = ImportedInlineFunctionStore()
        let deferredWork = loadImportedLibrarySymbols(
            options: ctx.options, symbols: symbols, types: types,
            diagnostics: ctx.diagnostics, interner: ctx.interner,
            importedInlineFunctions: importedInlineFunctions,
            phaseTimer: ctx.phaseTimer
        )
        if KklibSemaSession.shouldCache(options: ctx.options), !ctx.diagnostics.hasError {
            KklibSemaSession.store(
                options: ctx.options,
                symbols: symbols,
                types: types,
                interner: ctx.interner,
                work: deferredWork,
                importDiagnostics: Array(ctx.diagnostics.diagnostics.dropFirst(diagnosticStart))
            )
        }
        return (importedInlineFunctions, deferredWork)
    }

    /// Merges the stdlib artifact's imported symbols into `bundledIndex` so
    /// synthetic stub registration can see they are already covered (see
    /// `BundledSyntheticStubRegistration`'s callers). `stdlibModuleName` is
    /// resolved and validated once, in `loadImportedLibrarySymbols`, from
    /// manifest.json; take it from there rather than re-reading and
    /// re-parsing that file here. A second, independent read had no
    /// diagnostic on failure (unlike the first) and would silently return
    /// `bundledIndex` unchanged, so any suppression that depends on it
    /// (e.g. source-backed coroutine and collection registrations) would fail
    /// open — registering a synthetic stub the artifact already provides, which
    /// then wins overload resolution as the more specific candidate.
    func mergeImportedStdlibSymbolsIntoBundledIndex(
        bundledIndex: BundledDeclarationIndex,
        stdlibModuleName: InternedString,
        stdlibIndexSource: IndexedLibrarySource? = nil,
        precomputedMemberIndex: PrecomputedBundledMemberIndex? = nil,
        stdlibMemberKeys: Set<BundledMemberKey>? = nil,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> BundledDeclarationIndex {
        if let precomputedMemberIndex {
            var updatedIndex = bundledIndex
            updatedIndex.insertImportedStdlibSymbols(
                keys: [],
                interner: interner,
                precomputedMemberIndex: precomputedMemberIndex
            )
            return updatedIndex
        }
        // A compact-indexed stdlib artifact already carries every member's
        // (owner, name, arity) key. Reading them straight from the index keeps
        // the merge from scanning (and thereby registering) ~31k shells just
        // to answer "an imported declaration exists here". The scan's other
        // job — re-parenting extension functions to their receiver — is
        // identical to the per-registration fixup the source performs when an
        // entry drains, so already- and not-yet-registered records are both
        // covered.
        if let stdlibMemberKeys {
            var updatedIndex = bundledIndex
            updatedIndex.insertImportedStdlibSymbols(
                keys: stdlibMemberKeys,
                interner: interner
            )
            return updatedIndex
        }
        if let stdlibIndexSource {
            var updatedIndex = bundledIndex
            updatedIndex.insertImportedStdlibSymbols(
                keys: stdlibIndexSource.memberKeys(),
                interner: interner
            )
            return updatedIndex
        }
        // Resolve each nominal FQName once, including receivers from other
        // modules and names shared with package records. Successful lookups
        // remain valid because new symbols append after existing candidates.
        var nominalSymbols: [[InternedString]: SymbolID] = [:]
        var missingNominals: [[InternedString]: Int] = [:]
        func nominalSymbol(for fqName: [InternedString]) -> SymbolID? {
            if let cached = nominalSymbols[fqName] { return cached }
            // Eager signature queries can create nominal placeholders while
            // merging. Retry misses after the symbol table grows.
            let symbolCount = symbols.count
            if missingNominals[fqName] == symbolCount { return nil }
            if let owner = symbols.lookupAll(fqName: fqName).first(where: { id in
                switch symbols.symbol(id)?.kind {
                case .class, .interface, .object, .enumClass, .annotationClass: true
                default: false
                }
            }) {
                nominalSymbols[fqName] = owner
                return owner
            }
            missingNominals[fqName] = symbolCount
            return nil
        }

        var importedStdlibKeys: Set<BundledMemberKey> = []
        var retainedOverlaps: [BundledMemberKey: Bool] = [:]
        // Imports can claim existing symbols out of definition order. Keep
        // allSymbols' original order so lazy placeholder creation has the
        // same effect on subsequent parent fixups.
        let moduleSymbols = symbols.symbols(inModule: stdlibModuleName).sorted { $0.rawValue < $1.rawValue }
        for id in moduleSymbols {
            guard let symbol = symbols.symbol(id), symbol.flags.contains(.importedLibrary) else { continue }
            // `memberKey` answers arity/receiver-owner from the compact
            // `ImportedMemberIndexShape` when the symbol is an unmaterialized
            // lazy shell, so this scan does not decode declaration bodies.
            guard let key = BundledDeclarationIndex.memberKey(
                for: symbol, symbolID: symbol.id, symbols: symbols, types: types, interner: interner
            ) else { continue }
            importedStdlibKeys.insert(key)

            // STDLIB-SHARED-012: Source-backed extension functions imported from a
            // stdlib artifact must be attached to their receiver nominal type so
            // collection/sequence member-call fallback resolution (which keys off
            // parentSymbol == owner) can find them. Skip retained runtime-bridge
            // overlaps so synthetic ABI stubs keep routing through kk_* entries.
            //
            // Member extensions (`fun T.m(...)` declared inside a nominal type)
            // must keep their declaring owner as parent: re-parenting them to
            // the extension receiver would erase the dispatch receiver owner
            // member-extension calls need for the [dispatch, extension, args]
            // calling convention.
            guard symbol.kind == .function else { continue }
            let receiverSymbol: SymbolID
            if let shape = symbols.importedMemberIndexShape(for: symbol.id) {
                // Lazy shells carry the receiver's nominal FQ name in the
                // compact index, so the parent edge is restored without
                // materializing the callable signature. Most functions have
                // no extension receiver and need no parent fixup at all.
                guard let receiverFQName = shape.receiverOwnerFQName,
                      let owner = nominalSymbol(for: receiverFQName) else { continue }
                receiverSymbol = owner
            } else {
                guard let receiverType = symbols.functionSignature(for: symbol.id)?.receiverType,
                      let owner = BundledDeclarationIndex.receiverOwnerSymbol(for: receiverType, types: types)
                else { continue }
                receiverSymbol = owner
            }
            guard nominalSymbol(for: Array(symbol.fqName.dropLast())) == nil else { continue }
            let retained: Bool
            if let cached = retainedOverlaps[key] {
                retained = cached
            } else {
                retained = BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap(key, interner: interner)
                retainedOverlaps[key] = retained
            }
            guard !retained else { continue }
            symbols.setParentSymbol(receiverSymbol, for: symbol.id)
        }
        var updatedIndex = bundledIndex
        updatedIndex.insertImportedStdlibSymbols(keys: importedStdlibKeys, interner: interner)
        return updatedIndex
    }

    func collectAllHeaders(
        ast: ASTModule, fileScopes: [Int32: FileScope],
        symbols: SymbolTable, types: TypeSystem, bindings: BindingTable,
        ctx: CompilationContext,
        predeclared initialPredeclared: [DeclID: SymbolID] = [:]
    ) {
        // Collect bundled/residual stdlib headers before user headers so that
        // source-backed stdlib declarations (e.g. `kotlin.experimental`
        // annotation classes) are registered before user signatures that
        // reference them are resolved inline during header collection. This
        // keeps resolution independent of the order in which the SourceManager
        // assigned file IDs (the driver injects bundled sources first, but test
        // harnesses may add user sources first).
        let orderedFiles = ast.sortedFiles.sorted { lhs, rhs in
            let lhsBundled = ctx.sourceManager.origin(of: lhs.fileID)?.isBundledStdlib == true
            let rhsBundled = ctx.sourceManager.origin(of: rhs.fileID)?.isBundledStdlib == true
            if lhsBundled != rhsBundled {
                return lhsBundled
            }
            return lhs.fileID.rawValue < rhs.fileID.rawValue
        }
        let preparedHeaders = prepareFileHeaders(
            files: orderedFiles, arena: ast.arena,
            jobs: ctx.options.frontendFlags.contains("sema-parallel") ? ctx.frontendJobs : 1
        )
        // BUG-143: forward-declare every top-level nominal type first, so a
        // signature may reference a class/interface/object declared later in the
        // same file (or in a file collected later). Seeded with whatever
        // the early bundled nominal pass in `Phase.run` already predeclared;
        // `predeclareNominalTypeHeaders` skips declarations already present.
        var predeclared = initialPredeclared
        for file in orderedFiles {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            predeclareNominalTypeHeaders(
                file: file, ast: ast, symbols: symbols, scope: fileScope,
                sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics,
                interner: ctx.interner, into: &predeclared
            )
        }
        // Alias right-hand sides can reference nested types before their owners'
        // signatures are collected, including owners in later input files.
        for file in orderedFiles {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            for declID in file.topLevelDecls {
                guard let symbol = predeclared[declID] else { continue }
                predeclareNestedNominalTypeHeaders(
                    declID: declID, ownerSymbol: symbol, sourceFileID: file.fileID,
                    ast: ast, symbols: symbols, types: types, bindings: bindings,
                    scope: fileScope, ctx: ctx
                )
            }
        }
        // Numeric subtype and least-upper-bound checks use the canonical kotlin.Number symbol.
        resolveNumberClassSymbol(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        resolveUnitClassSymbol(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )

        // Type aliases are collected before the remaining headers so that their
        // underlying type is available to signatures that mention the alias.
        for collectsTypeAliases in [true, false] {
            for (file, prepared) in zip(orderedFiles, preparedHeaders) {
                guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
                if collectsTypeAliases {
                    registerFileAnnotations(
                        file: file,
                        symbols: symbols,
                        diagnostics: ctx.diagnostics,
                        interner: ctx.interner
                    )
                }
                for header in collectsTypeAliases ? prepared.aliases : prepared.remaining {
                    let declID = header.declarationID
                    collectHeader(
                        declID: declID, file: file, ast: ast,
                        symbols: symbols, types: types, bindings: bindings,
                        scope: fileScope, sourceManager: ctx.sourceManager,
                        diagnostics: ctx.diagnostics, interner: ctx.interner,
                        ctx: ctx, predeclaredSymbol: predeclared[declID],
                        preparedDeclaration: header.declaration
                    )
                }
            }
        }
    }

    private func runValidationPasses(
        ast: ASTModule, symbols: SymbolTable, bindings: BindingTable,
        types: TypeSystem, ctx: CompilationContext, sema: SemaModule
    ) {
        for declID in bindings.declSymbols.keys {
            guard case let .classDecl(classDecl) = ast.arena.decl(declID) else { continue }
            registerPrimaryConstructorPropertyAnnotations(
                for: classDecl, ast: ast, symbols: symbols, types: types, bindings: bindings,
                sourceManager: ctx.sourceManager, diagnostics: ctx.diagnostics, interner: ctx.interner
            )
        }
        canonicalizeDeclarationAnnotations(ast: ast, bindings: bindings, symbols: symbols, types: types, interner: ctx.interner)
        withSubPhaseTiming("bindInheritanceEdges", timer: ctx.phaseTimer) {
            bindInheritanceEdges(
                ast: ast, symbols: symbols, bindings: bindings, types: types,
                diagnostics: ctx.diagnostics, sourceManager: ctx.sourceManager, interner: ctx.interner
            )
        }
        withSubPhaseTiming("collectDataTypeGeneratedMembers", timer: ctx.phaseTimer) {
            collectDataTypeGeneratedMembersAfterInheritance(
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                types: types,
                interner: ctx.interner,
                diagnostics: ctx.diagnostics
            )
        }
        withSubPhaseTiming("registerChannelSendChannelSubtype", timer: ctx.phaseTimer) {
            registerChannelSendChannelSubtype(symbols: symbols, types: types, interner: ctx.interner)
        }
        // KSP-719: Restore kotlin.Any as the direct supertype of the bundled
        // kotlin.Annotation source, because its source declaration has no
        // explicit supertype clause and would otherwise erase the synthetic
        // supertype installed by registerSyntheticAnyStub.
        withSubPhaseTiming("patchBundledAnnotationSupertype", timer: ctx.phaseTimer) {
            patchBundledAnnotationSupertype(
                symbols: symbols,
                types: types,
                interner: ctx.interner
            )
        }
        // KSP-944: MutableList's source declaration owns its official
        // List/MutableCollection edges, while the retained compiler shell
        // still supplies the MutableIterable residual compatibility edge.
        withSubPhaseTiming("patchSourceBackedMutableListSupertypes", timer: ctx.phaseTimer) {
            patchSourceBackedMutableListSupertypes(
                symbols: symbols,
                types: types,
                interner: ctx.interner
            )
        }
        withSubPhaseTiming("registerAllEnumEntryDispatchFunctions", timer: ctx.phaseTimer) {
            registerAllEnumEntryDispatchFunctions(
                ast: ast,
                bindings: bindings,
                symbols: symbols,
                types: types,
                interner: ctx.interner
            )
        }
        withSubPhaseTiming("validateTypeParameterUpperBounds", timer: ctx.phaseTimer) {
            validateTypeParameterUpperBounds(
                symbols: symbols, types: types, interner: ctx.interner, diagnostics: ctx.diagnostics
            )
        }
        withSubPhaseTiming("validateTypeAliasCycles", timer: ctx.phaseTimer) {
            validateTypeAliasCycles(
                symbols: symbols, types: types, diagnostics: ctx.diagnostics
            )
        }
        withSubPhaseTiming("validateSealedHierarchy", timer: ctx.phaseTimer) {
            validateSealedHierarchy(
                ast: ast, symbols: symbols, bindings: bindings,
                diagnostics: ctx.diagnostics, interner: ctx.interner, sourceManager: ctx.sourceManager
            )
        }
        withSubPhaseTiming("validateClassDelegation", timer: ctx.phaseTimer) {
            validateClassDelegation(
                ast: ast, symbols: symbols, bindings: bindings, types: types,
                diagnostics: ctx.diagnostics, interner: ctx.interner
            )
        }
        if ctx.options.emit.isJVM {
            do { try ctx.jvmImports?.bind(in: ctx, sema: sema) }
            catch { ctx.diagnostics.error("KSWIFTK-JVM-0003", "Cannot bind JVM classpath: \(error)", range: nil) }
        }
        withSubPhaseTiming("validateAbstractOverrides", timer: ctx.phaseTimer) {
            validateAbstractOverrides(
                ast: ast, symbols: symbols, bindings: bindings, types: types,
                diagnostics: ctx.diagnostics, interner: ctx.interner
            )
        }
        withSubPhaseTiming("validateDiamondOverrides", timer: ctx.phaseTimer) {
            validateDiamondOverrides(
                ast: ast, symbols: symbols, bindings: bindings,
                diagnostics: ctx.diagnostics, interner: ctx.interner
            )
        }
        withSubPhaseTiming("validateOpenFinalOverride", timer: ctx.phaseTimer) {
            validateOpenFinalOverride(
                ast: ast, symbols: symbols, bindings: bindings, types: types,
                diagnostics: ctx.diagnostics, interner: ctx.interner,
                compilationModuleName: ctx.options.moduleName
            )
        }
        withSubPhaseTiming("validateExpectActualMatching", timer: ctx.phaseTimer) {
            validateExpectActualMatching(
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: ctx.diagnostics,
                interner: ctx.interner,
                commonModuleMode: ctx.options.isCommonModule
            )
        }
        withSubPhaseTiming("validateAnnotationTargets", timer: ctx.phaseTimer) {
            validateAnnotationTargets(
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                diagnostics: ctx.diagnostics,
                interner: ctx.interner,
                sourceManager: ctx.sourceManager
            )
        }
        withSubPhaseTiming("validateJsExportDeclarations", timer: ctx.phaseTimer) {
            validateJsExportDeclarations(
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                types: types,
                diagnostics: ctx.diagnostics,
                interner: ctx.interner,
                globalOptInMarkerNames: ctx.options.optInMarkerNames
            )
        }
        withSubPhaseTiming("validateJsStaticDeclarations", timer: ctx.phaseTimer) {
            validateJsStaticDeclarations(
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: ctx.diagnostics,
                interner: ctx.interner,
                globalOptInMarkerNames: ctx.options.optInMarkerNames
            )
        }
        withSubPhaseTiming("validateExperimentalTypeInferenceOptIn", timer: ctx.phaseTimer) {
            validateExperimentalTypeInferenceOptIn(
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: ctx.diagnostics
            )
        }
        withSubPhaseTiming("validateExperimentalVersionOverloadingOptIn", timer: ctx.phaseTimer) {
            validateExperimentalVersionOverloadingOptIn(
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: ctx.diagnostics,
                interner: ctx.interner,
                options: ctx.options
            )
        }
        withSubPhaseTiming("validateConstructorDelegation", timer: ctx.phaseTimer) {
            validateConstructorDelegation(ast: ast, symbols: symbols, diagnostics: ctx.diagnostics)
        }
        withSubPhaseTiming("validateDeclarationPositions", timer: ctx.phaseTimer) {
            validateDeclarationPositions(
                ast: ast, symbols: symbols, types: types,
                diagnostics: ctx.diagnostics, interner: ctx.interner,
                sourceManager: ctx.sourceManager,
                fullValueClassesEnabled: ctx.options.fullValueClassesEnabled
            )
        }
        withSubPhaseTiming("validateDeclarationSiteVariance", timer: ctx.phaseTimer) {
            validateDeclarationSiteVariance(
                ast: ast, symbols: symbols, bindings: bindings,
                types: types, diagnostics: ctx.diagnostics, interner: ctx.interner
            )
        }
        withSubPhaseTiming("synthesizeClassDelegationForwardingMethodSymbols", timer: ctx.phaseTimer) {
            synthesizeClassDelegationForwardingMethodSymbols(
                ast: ast, symbols: symbols, bindings: bindings,
                types: types, interner: ctx.interner
            )
        }
        // KUU-655: after delegation forwarders exist (so a `by`-delegated
        // interface method's forwarder inherits its defaults too), before
        // vtable/itable layout (layout only keys off arity/suspend, not
        // default flags, so ordering relative to it doesn't matter).
        withSubPhaseTiming("inheritDefaultArgumentValuesForOverrides", timer: ctx.phaseTimer) {
            inheritDefaultArgumentValuesForOverrides(symbols: symbols, types: types)
        }
        withSubPhaseTiming("inheritOperatorModifierForOverrides", timer: ctx.phaseTimer) {
            inheritOperatorModifierForOverrides(symbols: symbols, types: types, sourceManager: ctx.sourceManager)
        }
        withSubPhaseTiming("inheritInfixModifierForOverrides", timer: ctx.phaseTimer) {
            inheritInfixModifierForOverrides(symbols: symbols, types: types)
        }
        withSubPhaseTiming("synthesizeNominalLayouts", timer: ctx.phaseTimer) {
            synthesizeNominalLayouts(
                symbols: symbols, types: types,
                interner: ctx.interner, diagnostics: ctx.diagnostics
            )
        }
        withSubPhaseTiming("attachCompilerMetadataAnnotations", timer: ctx.phaseTimer) {
            attachCompilerMetadataAnnotations(
                symbols: symbols,
                types: types,
                moduleName: ctx.options.moduleName,
                interner: ctx.interner
            )
        }
    }

    private func runBodyAnalysis(
        ast: ASTModule, symbols: SymbolTable, types: TypeSystem,
        bindings: BindingTable, ctx: CompilationContext
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                analyzeBody(
                    declID: declID, ast: ast, symbols: symbols, types: types,
                    bindings: bindings, diagnostics: ctx.diagnostics, interner: ctx.interner
                )
            }
        }
    }
}
