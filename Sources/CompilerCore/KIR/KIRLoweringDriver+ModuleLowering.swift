
import Foundation

extension KIRLoweringDriver {
    func lowerModule(
        ast: ASTModule,
        sema: SemaModule,
        compilationCtx: CompilationContext
    ) -> KIRModule {
        ctx.resetModuleState()
        for file in ast.sortedFiles {
            let path = compilationCtx.sourceManager.path(of: file.fileID)
            guard !path.isEmpty, !path.hasPrefix("__bundled_") else { continue }
            let fileStem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            guard let firstCharacter = fileStem.first else { continue }
            let facadeName = firstCharacter.uppercased() + String(fileStem.dropFirst()) + "Kt"
            let packageName = file.packageFQName.map(compilationCtx.interner.resolve).joined(separator: ".")
            ctx.lambdaEnclosingClassNamesByFileID[file.fileID] = packageName.isEmpty
                ? facadeName
                : "\(packageName).\(facadeName)"
        }
        ctx.lazyThreadSafetyMode = compilationCtx.options.lazyThreadSafetyMode
        ctx.assertionsMode = compilationCtx.options.assertionsMode
        ctx.initializeSyntheticLambdaSymbolAllocator(
            sema: sema,
            stdlibOnly: compilationCtx.options.stdlibOnly
        )

        let arena = KIRArena()
        var files: [KIRFile] = []
        let sourceByFileID = buildSourceByFileID(ast: ast, compilationCtx: compilationCtx)
        let propertyConstantInitializers = constantCollector.collectPropertyConstantInitializers(
            ast: ast,
            sema: sema,
            interner: compilationCtx.interner,
            sourceByFileID: sourceByFileID
        )
        let shared = KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: compilationCtx.interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        ctx.setFunctionDefaultArguments(callSupportLowerer.collectFunctionDefaultArgumentExpressions(
            ast: ast,
            sema: sema
        ))

        // Using a single array ensures Kotlin's strict declaration-order initialization guarantee.
        var allTopLevelInitInstructions: KIRLoweringEmitContext = []

        // Maps delegated property symbol → delegate storage symbol (e.g. `$delegate_`).
        // We store the delegate handle into this storage symbol in main, and load it
        // at use-sites when rewriting getValue calls.
        var delegateStorageSymbolByPropertySymbol: [SymbolID: SymbolID] = [:]

        var skippedBundledFiles: [ASTFile] = []
        for file in ast.sortedFiles {
            if shouldSkipBundledFileForOutput(file, compilationCtx: compilationCtx) {
                skippedBundledFiles.append(file)
                continue
            }
            let declIDs = lowerTopLevelDecls(
                file: file,
                shared: shared,
                compilationCtx: compilationCtx,
                allTopLevelInitInstructions: &allTopLevelInitInstructions,
                delegateStorageSymbolByPropertySymbol: &delegateStorageSymbolByPropertySymbol
            )
            files.append(KIRFile(fileID: file.fileID, decls: declIDs))
        }

        // Synthetic companion anchors restored from the bundled library have
        // no source declaration in this module to allocate their singleton.
        // Materialize any referenced anchor, just as source-backed companions
        // allocate their singleton during declaration lowering.
        let syntheticCompanionDecls = synthesizeReferencedSyntheticCompanions(shared: shared)
        if !syntheticCompanionDecls.isEmpty, let firstFile = files.first {
            files[0] = KIRFile(fileID: firstFile.fileID, decls: firstFile.decls + syntheticCompanionDecls)
        }

        // Bundled stdlib files skipped from output can still be referenced by
        // enum constructor-property reads (e.g. `CpuArchitecture.ARM64.bitness`),
        // which are emitted as `$enumConstructorProperty$` placeholder calls.
        // The matching helper is only synthesized while lowering the enum's
        // ClassDecl, so skipped files leave the placeholder dangling all the
        // way to an unresolved-symbol link error. Synthesize helpers for the
        // skipped enums whose placeholders are actually called.
        synthesizeSkippedBundledEnumConstructorPropertyHelpers(
            skippedFiles: skippedBundledFiles,
            files: &files,
            shared: shared,
            compilationCtx: compilationCtx
        )

        // KUU-3675: compiler-synthetic and initializer-less imported
        // companion objects (e.g. `kotlin.String.Companion`) have no source
        // declaration and no artifact initializer, so nothing ever populated
        // their root slots. Synthesize eager handles for them before the
        // companion-initializer call list is built.
        let uninitializedCompanionDeclIDs = synthesizeUninitializedCompanionHandles(
            shared: shared
        )
        if !uninitializedCompanionDeclIDs.isEmpty {
            files.append(KIRFile(fileID: .invalid, decls: uninitializedCompanionDeclIDs))
        }

        // Object and companion handles must exist before any top-level
        // initializer can trigger their lazy bodies. Keep these allocation-only
        // calls ahead of user-visible property initialization.
        var orderedTopLevelInitInstructions: KIRLoweringEmitContext = []
        appendCompanionInitializerCalls(
            arena: arena, sema: sema,
            allTopLevelInitInstructions: &orderedTopLevelInitInstructions
        )

        appendImportedLibraryInitializerCalls(
            arena: arena,
            sema: sema,
            interner: compilationCtx.interner,
            allTopLevelInitInstructions: &orderedTopLevelInitInstructions
        )

        // Serialized `.klib` bodies: materialize imported functions, ctors,
        // accessors, member fields and singleton init into this arena so the
        // calls lowered above resolve to real definitions. A klib is a
        // dependency — its top-level initializers run before the consumer's
        // own, but after `.kklib` stubs and object pre-allocations.
        for loadedKlib in sema.klibModules {
            let lowerer = KlibBodyLowerer(
                loaded: loadedKlib,
                driver: self,
                sema: sema,
                arena: arena,
                interner: compilationCtx.interner,
                diagnostics: compilationCtx.diagnostics
            )
            let klibResult = lowerer.lowerModule()
            if let klibFile = klibResult.file {
                files.append(klibFile)
            }
            orderedTopLevelInitInstructions.appendRelocatingLabels(
                contentsOf: klibResult.topLevelInitInstructions
            )
        }

        orderedTopLevelInitInstructions.appendRelocatingLabels(
            contentsOf: allTopLevelInitInstructions
        )

        // A library has no `main` to receive its stored top-level property
        // initializers. Keep them as a callable entry point in the artifact;
        // importing modules call it before their own property initializers.
        // Object/companion initializers are imported separately, so this
        // entry point contains reflection registration and the library's own
        // property writes.
        if case .library = compilationCtx.options.emit,
           !allTopLevelInitInstructions.isEmpty || !ctx.allReflectionInitializers().isEmpty {
            let symbol = ctx.allocateSyntheticGeneratedSymbol()
            let name = compilationCtx.interner.intern(
                "__kk_library_top_level_init_\(compilationCtx.options.moduleName)"
            )
            var body: KIRLoweringEmitContext = [.beginBlock]
            for initializer in ctx.allReflectionInitializers() {
                let result = arena.appendTemporary(type: sema.types.unitType)
                body.append(.call(
                    symbol: initializer.symbol, callee: initializer.name,
                    arguments: [], result: result, canThrow: false
                ))
            }
            body.appendRelocatingLabels(contentsOf: allTopLevelInitInstructions)
            body.append(.returnUnit)
            body.append(.endBlock)
            _ = arena.appendDecl(.function(KIRFunction(
                symbol: symbol,
                name: name,
                params: [],
                returnType: sema.types.unitType,
                body: body.instructions,
                isSuspend: false,
                isInline: false,
                instructionLocations: body.instructionLocations
            )))
        }

        emitSyntheticTopLevelExternalPropertyInitializers(
            arena: arena,
            sema: sema,
            interner: compilationCtx.interner,
            allTopLevelInitInstructions: &orderedTopLevelInitInstructions
        )

        postProcessTopLevelInitializersAndDelegates(
            ast: ast,
            sema: sema,
            compilationCtx: compilationCtx,
            arena: arena,
            allTopLevelInitInstructions: orderedTopLevelInitInstructions,
            delegateStorageSymbolByPropertySymbol: delegateStorageSymbolByPropertySymbol
        )
        emitAnnotationFactories(shared: shared, compilationCtx: compilationCtx)
        resolveDeferredObjectLazyInitGuards(arena: arena)
        insertEnumLazyInitTriggers(arena: arena, sema: sema, interner: compilationCtx.interner)
        let module = KIRModule(files: files, arena: arena)
        module.arena.callableValueInfoByExprID = ctx.callableValueInfoByExprID
        module.arena.receiverFirstLauncherLambdaSymbols = ctx.receiverFirstLauncherLambdaSymbols
        return module
    }

    private func synthesizeSkippedBundledEnumConstructorPropertyHelpers(
        skippedFiles: [ASTFile],
        files: inout [KIRFile],
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) {
        guard !skippedFiles.isEmpty else { return }
        let sema = shared.sema
        let ast = shared.ast
        let arena = shared.arena
        let interner = compilationCtx.interner
        let prefixes = [EnumPropertyHelperNames.getterPrefix, EnumPropertyHelperNames.setterPrefix]

        var neededOwnerIDs = Set<Int32>()
        for decl in arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { continue }
                let calleeName = interner.resolve(callee)
                guard let prefix = prefixes.first(where: { calleeName.hasPrefix($0) }) else { continue }
                let remainder = calleeName.dropFirst(prefix.count)
                guard let separatorIndex = remainder.firstIndex(of: "$"),
                      let ownerID = Int32(remainder[..<separatorIndex])
                else { continue }
                neededOwnerIDs.insert(ownerID)
            }
        }
        guard !neededOwnerIDs.isEmpty else { return }

        for file in skippedFiles {
            var helperDeclIDs: [KIRDeclID] = []
            // Enums can be nested under objects/interfaces too, so walk the
            // whole declaration tree rather than top-level classes only.
            func synthesizeIfNeeded(declID: DeclID) {
                guard let decl = ast.arena.decl(declID) else { return }
                var deeper: [DeclID] = []
                switch decl {
                case let .classDecl(classDecl):
                    if let symbol = sema.bindings.declSymbols[declID],
                       neededOwnerIDs.contains(symbol.rawValue)
                    {
                        helperDeclIDs.append(contentsOf: synthesizeEnumConstructorPropertyHelperFunctions(
                            classDecl: classDecl,
                            ownerSymbol: symbol,
                            shared: shared,
                            compilationCtx: compilationCtx
                        ))
                    }
                    deeper = classDecl.nestedClasses + classDecl.nestedObjects
                    if let companionDeclID = classDecl.companionObject {
                        deeper.append(companionDeclID)
                    }
                case let .objectDecl(objectDecl):
                    deeper = objectDecl.nestedClasses + objectDecl.nestedObjects
                case let .interfaceDecl(interfaceDecl):
                    deeper = interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                    if let companionDeclID = interfaceDecl.companionObject {
                        deeper.append(companionDeclID)
                    }
                default:
                    break
                }
                for nestedDeclID in deeper {
                    synthesizeIfNeeded(declID: nestedDeclID)
                }
            }
            for declID in file.topLevelDecls {
                synthesizeIfNeeded(declID: declID)
            }
            if !helperDeclIDs.isEmpty {
                files.append(KIRFile(fileID: file.fileID, decls: helperDeclIDs))
            }
        }
    }

    func shouldSkipBundledFileForOutput(
        _ file: ASTFile,
        compilationCtx: CompilationContext
    ) -> Bool {
        guard compilationCtx.sourceManager.origin(of: file.fileID)?.isBundledStdlib == true else {
            return false
        }

        // When emitting a dedicated stdlib .kklib, the bundled/residual source
        // bodies must be lowered into objects and inline-KIR artifacts.
        if compilationCtx.options.stdlibOnly {
            return false
        }

        switch compilationCtx.options.emit {
        case .kirDump:
            return true
        case .executable, .object, .llvmIR, .library, .jvmClass, .jvmJar:
            // Source-backed library calls need the same bundled definitions as
            // executables. Without bodies or imported link names, codegen falls
            // back to bare declaration names that no consumer can resolve.
            return false
        }
    }

    private func buildSourceByFileID(
        ast: ASTModule, compilationCtx: CompilationContext
    ) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for file in ast.files {
            let contents = compilationCtx.sourceManager.contents(of: file.fileID)
            result[file.fileID.rawValue] = String(data: contents, encoding: .utf8) ?? ""
        }
        return result
    }


    private func lowerTopLevelDecls(
        file: ASTFile,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext,
        delegateStorageSymbolByPropertySymbol: inout [SymbolID: SymbolID]
    ) -> [KIRDeclID] {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena

        var declIDs: [KIRDeclID] = []
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }

            switch decl {
            case let .classDecl(classDecl):
                // The actual enum owns the runtime slots and reflection wrappers.
                if sema.symbols.symbol(symbol)?.kind == .enumClass,
                   sema.symbols.symbol(symbol)?.flags.contains(.expectDeclaration) == true
                {
                    continue
                }
                declIDs.append(contentsOf: lowerTopLevelClassDecl(
                    classDecl,
                    symbol: symbol,
                    shared: shared,
                    compilationCtx: compilationCtx
                ))

            case let .interfaceDecl(interfaceDecl):
                declIDs.append(contentsOf: lowerTopLevelInterfaceDecl(
                    interfaceDecl, symbol: symbol, shared: shared,
                    compilationCtx: compilationCtx
                ))

            case let .objectDecl(objectDecl):
                declIDs.append(contentsOf: lowerTopLevelObjectDecl(
                    objectDecl, symbol: symbol, shared: shared,
                    compilationCtx: compilationCtx
                ))

            case let .funDecl(function):
                if sema.unreachableTopLevelFunctionDecls.contains(declID) { continue }
                declIDs.append(contentsOf: lowerTopLevelFunDecl(
                    function,
                    symbol: symbol,
                    shared: shared,
                    compilationCtx: compilationCtx
                ))

            case let .propertyDecl(propertyDecl):
                declIDs.append(contentsOf: lowerTopLevelPropertyDecl(
                    propertyDecl, symbol: symbol,
                    shared: shared, compilationCtx: compilationCtx,
                    allTopLevelInitInstructions: &allTopLevelInitInstructions,
                    delegateStorageSymbolByPropertySymbol: &delegateStorageSymbolByPropertySymbol
                ))

            case .typeAliasDecl:
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                declIDs.append(kirID)

            case .enumEntryDecl:
                let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                declIDs.append(kirID)
            }
        }
        return declIDs
    }


    private func lowerTopLevelInterfaceDecl(
        _ interfaceDecl: InterfaceDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let arena = shared.arena
        var ifaceNestedObjects = interfaceDecl.nestedObjects
        if let companionDeclID = interfaceDecl.companionObject {
            ifaceNestedObjects.append(companionDeclID)
        }
        // BUG-274: register the companion's lazy-init entry before lowering
        // this interface's own (default-body) member functions, which can
        // reference the companion -- see the matching comment in
        // `lowerTopLevelClassDecl`.
        var declIDs = synthesizeCompanionInitializerIfNeeded(
            companionDeclID: interfaceDecl.companionObject,
            ownerSymbol: symbol,
            shared: shared
        )
        let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
            memberFunctions: interfaceDecl.memberFunctions,
            memberProperties: interfaceDecl.memberProperties,
            nestedClasses: interfaceDecl.nestedClasses,
            nestedObjects: ifaceNestedObjects,
            shared: shared,
            compilationCtx: compilationCtx,
            isInterfaceContext: true
        )
        let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: directMembers)))
        declIDs.append(kirID)
        declIDs.append(contentsOf: allDecls)
        // Interfaces declare no `<init>` symbols, so this emits the
        // member-registration half only (KUU-4065).
        declIDs.append(contentsOf: synthesizeNominalReflectionInitializer(
            ownerSymbol: symbol,
            ownerName: interfaceDecl.name,
            ownerRange: interfaceDecl.range,
            shared: shared
        ))
        lowerNestedClassConstructors(
            nestedDecls: interfaceDecl.nestedClasses + ifaceNestedObjects,
            shared: shared,
            compilationCtx: compilationCtx,
            declIDs: &declIDs
        )
        return declIDs
    }


    private func lowerTopLevelObjectDecl(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let (directMembers, allDecls) = memberLowerer.lowerMemberDecls(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            shared: shared,
            compilationCtx: compilationCtx
        )
        let forwardingDecls = synthesizeClassDelegationForwardingMethods(
            classSymbol: symbol, shared: shared, compilationCtx: compilationCtx
        ) + synthesizeClassDelegationForwardingPropertyAccessors(
            classSymbol: symbol, shared: shared, compilationCtx: compilationCtx
        )
        let kirID = arena.appendDecl(.nominalType(KIRNominalType(
            symbol: symbol, memberDecls: directMembers + forwardingDecls
        )))
        var declIDs = [kirID]
        declIDs.append(contentsOf: allDecls)
        declIDs.append(contentsOf: forwardingDecls)
        // Objects declare no `<init>` symbols, so this emits the
        // member-registration half only (KUU-4065).
        declIDs.append(contentsOf: synthesizeNominalReflectionInitializer(
            ownerSymbol: symbol,
            ownerName: objectDecl.name,
            ownerRange: objectDecl.range,
            shared: shared
        ))
        lowerNestedClassConstructors(
            nestedDecls: objectDecl.nestedClasses + objectDecl.nestedObjects,
            shared: shared,
            compilationCtx: compilationCtx,
            declIDs: &declIDs
        )

        // Every source-backed top-level object needs a global slot for its
        // singleton heap pointer. Without it, an object crossing an Any
        // boundary is lowered as an unresolved symbol reference and reaches
        // the runtime as the raw zero value instead of a registered handle.
        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: symbol, args: [], nullability: .nonNull
        )))
        let globalID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: objectType)))
        declIDs.append(globalID)

        declIDs.append(contentsOf: synthesizeObjectInitializer(
            objectDecl,
            objectSymbol: symbol,
            shared: shared
        ))
        return declIDs
    }


    private func emitSyntheticTopLevelExternalPropertyInitializers(
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext
    ) {
        var existingGlobals: Set<SymbolID> = []
        for declaration in arena.declarations {
            guard case let .global(global) = declaration else { continue }
            existingGlobals.insert(global.symbol)
        }

        for symbolInfo in sema.symbols.allSymbols()
        where symbolInfo.kind == .property || symbolInfo.kind == .field || symbolInfo.kind == .backingField
        {
            let symbol = symbolInfo.id
            // Most imported properties have accessor links, not external
            // global initializers. Reject them before querying semantic types.
            guard let externalLinkName = sema.symbols.externalLinkNameIfKnown(for: symbol),
                  !externalLinkName.isEmpty,
                  !existingGlobals.contains(symbol)
            else { continue }
            let parentKind = sema.symbols.parentSymbolIfKnown(for: symbol).flatMap {
                sema.symbols.symbol($0)?.kind
            }
            // Compact indexes mark extension receivers at registration; only
            // a pending shell on an older index needs the decoded receiver
            // type to reach the same answer.
            guard parentKind == nil || parentKind == .package || parentKind == .object,
                  sema.symbols.backingFieldSymbol(for: symbol) == nil,
                  !sema.symbols.hasExtensionPropertyReceiver(symbol),
                  (!sema.symbols.hasPendingImportedMetadata(for: symbol)
                      || sema.symbols.extensionPropertyReceiverType(for: symbol) == nil),
                  let propertyType = sema.symbols.propertyType(for: symbol)
            else {
                continue
            }

            _ = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propertyType)))
            existingGlobals.insert(symbol)

            let result = arena.appendTemporary(type: propertyType
            )
            let storage = arena.appendExpr(
                .symbolRef(symbol),
                type: propertyType
            )

            let getterArguments = externalGlobalPropertyGetterArguments(
                for: symbol, sema: sema, arena: arena, into: &allTopLevelInitInstructions
            )
            allTopLevelInitInstructions.append(
                .call(callee: interner.intern(externalLinkName), arguments: getterArguments, result: result, canThrow: false)
            )
            allTopLevelInitInstructions.append(
                .copy(from: result, to: storage)
            )
        }
    }

    private func appendImportedLibraryInitializerCalls(
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext
    ) {
        func appendInitializer(_ initializerSymbol: SymbolID?) {
            guard let initializerSymbol else { return }
            guard let externalLinkName = sema.symbols.externalLinkNameIfKnown(for: initializerSymbol),
                  !externalLinkName.isEmpty
            else {
                return
            }
            let result = arena.appendTemporary(type: sema.types.unitType)
            allTopLevelInitInstructions.append(
                .call(symbol: initializerSymbol, callee: interner.intern(externalLinkName), arguments: [], result: result, canThrow: false)
            )
        }

        let importedSymbols = sema.symbols.allSymbols().filter { $0.flags.contains(.importedLibrary) }

        // Imported top-level properties can capture an object singleton. Make
        // every imported object's eager handle (and its interface registrations)
        // available before enum or library property initialization. Keeping
        // these in one symbol-order pass let a library initializer run before
        // its object initializer, leaving interface-typed singleton properties
        // with a null receiver in the consuming module.
        for symbol in importedSymbols {
            guard sema.symbols.mayHaveImportedInitializers(for: symbol.id) else { continue }
            // Complete indexes (v3) synthesized the initializer shells at
            // registration; anything older can only be discovered by decoding
            // the body record, which is exactly what the forcing getters do.
            let forceDecode = sema.symbols.importedInitializerInfoIsIncomplete(for: symbol.id)
            switch symbol.kind {
            case .object:
                appendInitializer(
                    forceDecode
                        ? sema.symbols.objectInitializerSymbol(for: symbol.id)
                        : sema.symbols.objectInitializerSymbolIfKnown(for: symbol.id)
                )
            case .class, .interface, .annotationClass:
                appendInitializer(
                    forceDecode
                        ? sema.symbols.companionObjectInitializerSymbol(for: symbol.id)
                        : sema.symbols.companionObjectInitializerSymbolIfKnown(for: symbol.id)
                )
            case .enumClass:
                appendInitializer(
                    forceDecode
                        ? sema.symbols.companionObjectInitializerSymbol(for: symbol.id)
                        : sema.symbols.companionObjectInitializerSymbolIfKnown(for: symbol.id)
                )
            default:
                break
            }
        }

        // Enum entry initialization may itself access imported singletons, so
        // keep it after all object and companion handles have been allocated.
        for symbol in importedSymbols where symbol.kind == .enumClass {
            appendInitializer(
                sema.symbols.importedInitializerInfoIsIncomplete(for: symbol.id)
                    ? sema.symbols.enumStaticInitSymbol(for: symbol.id)
                    : sema.symbols.enumStaticInitSymbolIfKnown(for: symbol.id)
            )
        }

        // Run library stored-property initializers only after singleton handles
        // and enum entries have been prepared. Keep the existing imported-symbol
        // order among libraries' top-level initializer calls.
        for symbol in importedSymbols where symbol.kind == .function {
            guard interner.resolve(symbol.name).hasPrefix("__kk_library_top_level_init_") else { continue }
            appendInitializer(symbol.id)
        }
    }

    private func appendCompanionInitializerCalls(
        arena: KIRArena,
        sema: SemaModule,
        allTopLevelInitInstructions: inout KIRLoweringEmitContext
    ) {
        let companionInitializers = ctx.allCompanionInitializers()
        guard !companionInitializers.isEmpty else { return }
        for initializer in companionInitializers {
            let result = arena.appendTemporary(type: sema.types.unitType
            )
            allTopLevelInitInstructions.append(
                .call(symbol: initializer.symbol, callee: initializer.name, arguments: [], result: result, canThrow: false)
            )
        }
    }
}
