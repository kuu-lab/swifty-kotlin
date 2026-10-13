import Foundation

extension DataFlowSemaPhase {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func collectHeader(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        ctx: CompilationContext,
        predeclaredSymbol: SymbolID? = nil
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        let package = file.packageFQName
        let anyType = types.anyType
        let unitType = types.unitType

        guard let declaration = topLevelDeclarationDescriptor(
            for: decl,
            diagnostics: diagnostics
        ) else { return }
        let fqName = package + [declaration.name]
        let symbol = predeclaredSymbol ?? defineTopLevelSymbol(
            declaration: declaration,
            decl: decl,
            file: file,
            symbols: symbols,
            scope: scope,
            sourceManager: sourceManager,
            diagnostics: diagnostics,
            interner: interner
        )
        bindings.bindDecl(declID, symbol: symbol)

        if case let .funDecl(funDecl) = decl {
            diagnoseReservedExternalFunctionUse(
                funDecl,
                sourceFileID: file.fileID,
                sourceManager: sourceManager,
                diagnostics: diagnostics
            )
        }
        registerAnnotations(
            for: decl,
            symbol: symbol,
            declRange: declaration.range,
            sourceFileID: file.fileID,
            sourceFile: file,
            sourceManager: sourceManager,
            interner: interner,
            symbols: symbols,
            diagnostics: diagnostics
        )
        attachUuidSourceMigrationClassAnnotationIfNeeded(
            to: symbol,
            fqName: fqName,
            sourceFileID: file.fileID,
            ctx: ctx,
            symbols: symbols,
            interner: interner
        )

        switch decl {
        case let .classDecl(classDecl):
            // Register class type parameters as symbols so member functions
            // can reference them (e.g. `fun get(): T` inside `class Box<T>`).
            let classTypeParamResult = registerNominalTypeParameters(
                classDecl.typeParams,
                ownerSymbol: symbol,
                fqName: fqName,
                namespacePrefix: "$class",
                declSite: classDecl.range,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            )
            let classTypeParamSymbols = classTypeParamResult.symbols
            let classLocalTypeParameters = classTypeParamResult.localMap

            // Create owner type with type parameter references as args
            let typeParamArgs: [TypeArg] = classTypeParamSymbols.map { tpSymbol in
                .invariant(types.make(.typeParam(TypeParamType(symbol: tpSymbol))))
            }
            let classType = types.make(.classType(ClassType(classSymbol: symbol, args: typeParamArgs, nullability: .nonNull)))
            let classScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: symbol,
                thisType: classType
            )
            collectNestedTypeAliases(
                classDecl.nestedTypeAliases,
                ownerFQName: fqName,
                sourceFileID: file.fileID,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )

            // Nested class/object headers must be collected before the primary
            // constructor parameter types are resolved, because those parameter
            // types (or their default values) may reference a nested type
            // (e.g. `annotation class RequiresOptIn(val level: Level = Level.ERROR)`).
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: [],
                    properties: [],
                    nestedClasses: classDecl.nestedClasses,
                    nestedObjects: classDecl.nestedObjects
                ),
                owner: OwnerContext(fqName: fqName, symbol: symbol, type: classType),
                sourceFileID: file.fileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: classScope,
                diagnostics: diagnostics,
                interner: interner,
                classTypeParameterSymbols: classTypeParamSymbols,
                classLocalTypeParameters: classLocalTypeParameters
            )

            let ctorName = interner.intern("<init>")
            let primaryCtorFQName = fqName + [ctorName]

            // Kotlin rule: only define a primary constructor symbol when either
            // (a) the class header has explicit constructor parentheses
            //     (`class Foo()` or `class Foo(x: Int)`), or
            // (b) there are no secondary constructors (implicit default ctor).
            // A class like `class Foo { constructor(x: Int) : ... }` has NO
            // primary constructor and should not get a synthetic no-arg ctor.
            let hasPrimaryCtorSyntax = classDecl.hasPrimaryConstructorSyntax
            let hasSecondaryCtors = !classDecl.secondaryConstructors.isEmpty
            if hasPrimaryCtorSyntax || !hasSecondaryCtors {
                let primaryCtorVisibilityDetail = primaryConstructorVisibilityDetail(
                    for: classDecl,
                    classKind: declaration.kind,
                    declarationVisibility: declaration.visibility
                )
                let primaryCtorSymbol = symbols.define(
                    kind: .constructor,
                    name: declaration.name,
                    fqName: primaryCtorFQName,
                    declSite: classDecl.range,
                    visibility: primaryCtorVisibilityDetail.visibility,
                    flags: primaryCtorVisibilityDetail.isInheritedFromOwner ? [.constructorVisibilityInherited] : []
                )
                scope.insert(primaryCtorSymbol)
                symbols.setParentSymbol(symbol, for: primaryCtorSymbol)
                do {
                    let localNamespaceFQName = primaryCtorFQName + [interner.intern("$\(primaryCtorSymbol.rawValue)")]
                    let params = collectValueParameters(
                        classDecl.primaryConstructorParams,
                        localNamespaceFQName: localNamespaceFQName,
                        declSite: classDecl.range,
                        ast: ast, symbols: symbols, types: types,
                        interner: interner,
                        localTypeParameters: classLocalTypeParameters,
                        relativeOwnerFQName: fqName,
                        currentPackageFQName: package,
                        imports: file.imports,
                        diagnostics: diagnostics,
                        fallbackType: anyType
                    )
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: classType,
                            parameterTypes: params.paramTypes,
                            returnType: classType,
                            valueParameterSymbols: params.paramSymbols,
                            valueParameterHasDefaultValues: params.paramHasDefaultValues,
                            valueParameterIsVararg: params.paramIsVararg,
                            valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                            typeParameterSymbols: classTypeParamSymbols,
                            classTypeParameterCount: classTypeParamSymbols.count
                        ),
                        for: primaryCtorSymbol
                    )
                    registerAnnotations(
                        classDecl.primaryConstructorAnnotations,
                        symbol: primaryCtorSymbol,
                        declRange: classDecl.range,
                        sourceFileID: file.fileID,
                        sourceFile: file,
                        sourceManager: sourceManager,
                        interner: interner,
                        symbols: symbols,
                        diagnostics: diagnostics
                    )
                }
            }

            for (ctorIndex, secondaryCtor) in classDecl.secondaryConstructors.enumerated() {
                let secCtorVisibilityDetail = constructorVisibilityDetail(
                    explicitModifiers: secondaryCtor.modifiers,
                    classKind: declaration.kind,
                    isSealedClass: classDecl.modifiers.contains(.sealed),
                    declarationVisibility: declaration.visibility
                )
                let secCtorSymbol = symbols.define(
                    kind: .constructor,
                    name: declaration.name,
                    fqName: primaryCtorFQName,
                    declSite: secondaryCtor.range,
                    visibility: secCtorVisibilityDetail.visibility,
                    flags: secCtorVisibilityDetail.isInheritedFromOwner ? [.constructorVisibilityInherited] : []
                )
                scope.insert(secCtorSymbol)
                symbols.setParentSymbol(symbol, for: secCtorSymbol)
                let localNamespaceFQName = primaryCtorFQName + [interner.intern("$sec\(ctorIndex)_\(secCtorSymbol.rawValue)")]
                let params = collectValueParameters(
                    secondaryCtor.valueParams,
                    localNamespaceFQName: localNamespaceFQName,
                    declSite: secondaryCtor.range,
                    ast: ast, symbols: symbols, types: types,
                    interner: interner,
                    localTypeParameters: classLocalTypeParameters,
                    relativeOwnerFQName: fqName,
                    currentPackageFQName: package,
                    imports: file.imports,
                    diagnostics: diagnostics,
                    fallbackType: anyType
                )
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: classType,
                        parameterTypes: params.paramTypes,
                        returnType: classType,
                        valueParameterSymbols: params.paramSymbols,
                        valueParameterHasDefaultValues: params.paramHasDefaultValues,
                        valueParameterIsVararg: params.paramIsVararg,
                        valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                        typeParameterSymbols: classTypeParamSymbols,
                        classTypeParameterCount: classTypeParamSymbols.count
                    ),
                    for: secCtorSymbol
                )
                registerAnnotations(
                    secondaryCtor.annotations,
                    symbol: secCtorSymbol,
                    declRange: secondaryCtor.range,
                    sourceFileID: file.fileID,
                    sourceFile: file,
                    sourceManager: sourceManager,
                    interner: interner,
                    symbols: symbols,
                    diagnostics: diagnostics
                )
            }

            // Value class validation: must have exactly one primary constructor parameter
            if isValueClassDeclaration(classDecl) {
                let valParams = classDecl.primaryConstructorParams
                if valParams.count != 1 {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0070",
                        "Value class must have exactly one primary constructor parameter.",
                        range: classDecl.range
                    )
                } else {
                    // Record the underlying type of the value class
                    let singleParam = valParams[0]
                    let underlyingType = resolveTypeRef(
                        singleParam.type,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        localTypeParameters: classLocalTypeParameters,
                        relativeOwnerFQName: fqName,
                        currentPackageFQName: package,
                        imports: file.imports,
                        diagnostics: diagnostics,
                        usageRange: classDecl.range
                    ) ?? anyType
                    symbols.setValueClassUnderlyingType(underlyingType, for: symbol)
                }
                if !classDecl.secondaryConstructors.isEmpty {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0071",
                        "Value class cannot have secondary constructors.",
                        range: classDecl.range
                    )
                }
            }

            if declaration.kind == .enumClass {
                for entry in classDecl.enumEntries {
                    let entryFQName = fqName + [entry.name]
                    let entryFlags = inheritedExpectActualFlags(
                        [],
                        from: symbol,
                        symbols: symbols,
                        includingActual: true
                    )
                    checkAndReportDuplicateDeclaration(
                        newKind: .field,
                        fqName: entryFQName,
                        range: entry.range,
                        symbols: symbols,
                        diagnostics: diagnostics,
                        newFlags: entryFlags
                    )
                    let entrySymbol = symbols.define(
                        kind: .field,
                        name: entry.name,
                        fqName: entryFQName,
                        declSite: entry.range,
                        visibility: .public,
                        flags: entryFlags
                    )
                    symbols.setParentSymbol(symbol, for: entrySymbol)
                    symbols.setPropertyType(classType, for: entrySymbol)
                    classScope.insert(entrySymbol)
                }
                collectEnumEntryMemberHeaders(
                    entries: classDecl.enumEntries,
                    ownerFQName: fqName,
                    ownerSymbol: symbol,
                    enumType: classType,
                    sourceFileID: file.fileID,
                    ctx: ctx,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: classScope,
                    diagnostics: diagnostics,
                    interner: interner,
                    classTypeParameterSymbols: classTypeParamSymbols,
                    classLocalTypeParameters: classLocalTypeParameters
                )
                collectSyntheticEnumEntryProperties(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner
                )
                collectSyntheticEnumValuesMember(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    enumType: classType,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner
                )
            }
            if declaration.flags.contains(.dataType) {
                collectSyntheticDataClassMethods(
                    classDecl: classDecl,
                    ast: ast,
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: classType,
                    phase: .beforeMemberHeaders,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner,
                    diagnostics: diagnostics,
                    localTypeParameters: classLocalTypeParameters
                )
            }
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: classDecl.memberFunctions,
                    properties: classDecl.memberProperties,
                    nestedClasses: [],
                    nestedObjects: []
                ),
                owner: OwnerContext(fqName: fqName, symbol: symbol, type: classType),
                sourceFileID: file.fileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: classScope,
                diagnostics: diagnostics,
                interner: interner,
                classTypeParameterSymbols: classTypeParamSymbols,
                classLocalTypeParameters: classLocalTypeParameters
            )
            if declaration.flags.contains(.dataType) {
                collectSyntheticDataClassMethods(
                    classDecl: classDecl,
                    ast: ast,
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: classType,
                    phase: .afterMemberHeaders,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner,
                    diagnostics: diagnostics,
                    localTypeParameters: classLocalTypeParameters
                )
            }
            if declaration.kind == .annotationClass {
                collectSyntheticHashCode(
                    ownerSymbol: symbol, ownerFQName: fqName, ownerType: classType,
                    requireDataTypeFlag: false, symbols: symbols, types: types,
                    scope: classScope, interner: interner
                )
                collectSyntheticToString(
                    ownerSymbol: symbol, ownerFQName: fqName, ownerType: classType,
                    requireDataTypeFlag: false, symbols: symbols, types: types,
                    scope: classScope, interner: interner
                )
                collectSyntheticEquals(
                    ownerSymbol: symbol, ownerFQName: fqName, ownerType: classType,
                    requireDataTypeFlag: false, symbols: symbols, types: types,
                    scope: classScope, interner: interner
                )
            }
            if symbols.symbol(symbol)?.flags.contains(.valueType) == true {
                // Collect after explicit members so an override suppresses synthesis.
                collectSyntheticToString(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: classType,
                    requireDataTypeFlag: false,
                    symbols: symbols,
                    types: types,
                    scope: classScope,
                    interner: interner
                )
            }
            // Process companion object: register as nested object and link to owner class
            if let companionDeclID = classDecl.companionObject {
                collectCompanionObjectHeader(
                    companionDeclID: companionDeclID,
                    ownerFQName: fqName,
                    ownerSymbol: symbol,
                    ownerType: classType,
                    sourceFileID: file.fileID,
                    ctx: ctx,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: classScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            } else if declaration.kind == .enumClass {
                // Synthesize implicit companion for enum classes (valueOf, entries)
                let companionName = interner.intern("Companion")
                let companionFQName = fqName + [companionName]
                let companionSymbol = symbols.define(
                    kind: .object,
                    name: companionName,
                    fqName: companionFQName,
                    declSite: classDecl.range,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(symbol, for: companionSymbol)
                symbols.setCompanionObjectSymbol(companionSymbol, for: symbol)
                classScope.insert(companionSymbol)
                let companionType = types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                let companionScope = ClassMemberScope(
                    parent: classScope,
                    symbols: symbols,
                    ownerSymbol: companionSymbol,
                    thisType: companionType
                )
                collectSyntheticEnumCompanionMembers(
                    companionSymbol: companionSymbol,
                    companionFQName: companionFQName,
                    enumType: classType,
                    symbols: symbols,
                    types: types,
                    scope: companionScope,
                    interner: interner
                )
            }

        case let .interfaceDecl(interfaceDecl):
            // Register interface type parameters as symbols
            let ifaceTypeParamResult = registerNominalTypeParameters(
                interfaceDecl.typeParams,
                ownerSymbol: symbol,
                fqName: fqName,
                namespacePrefix: "$iface",
                declSite: interfaceDecl.range,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            )
            let ifaceTypeParamSymbols = ifaceTypeParamResult.symbols
            let ifaceLocalTypeParameters = ifaceTypeParamResult.localMap

            let ifaceTypeParamArgs: [TypeArg] = ifaceTypeParamSymbols.map { tpSymbol in
                .invariant(types.make(.typeParam(TypeParamType(symbol: tpSymbol))))
            }
            let interfaceType = types.make(.classType(ClassType(classSymbol: symbol, args: ifaceTypeParamArgs, nullability: .nonNull)))
            let interfaceScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: symbol,
                thisType: interfaceType
            )
            collectNestedTypeAliases(
                interfaceDecl.nestedTypeAliases,
                ownerFQName: fqName,
                sourceFileID: file.fileID,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: interfaceDecl.memberFunctions,
                    properties: interfaceDecl.memberProperties,
                    nestedClasses: interfaceDecl.nestedClasses,
                    nestedObjects: interfaceDecl.nestedObjects
                ),
                owner: OwnerContext(fqName: fqName, symbol: symbol, type: interfaceType),
                sourceFileID: file.fileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: interfaceScope,
                diagnostics: diagnostics,
                interner: interner,
                classTypeParameterSymbols: ifaceTypeParamSymbols,
                classLocalTypeParameters: ifaceLocalTypeParameters
            )
            // Process companion object for interface
            if let companionDeclID = interfaceDecl.companionObject {
                collectCompanionObjectHeader(
                    companionDeclID: companionDeclID,
                    ownerFQName: fqName,
                    ownerSymbol: symbol,
                    ownerType: interfaceType,
                    sourceFileID: file.fileID,
                    ctx: ctx,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: interfaceScope,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }

        case let .objectDecl(objectDecl):
            // Unit keeps its builtin value representation, but its source-backed
            // object symbol must remain available for ordinary member dispatch.
            let builtinNames = BuiltinTypeNames(interner: interner)
            let isUnitObject = package == [interner.intern("kotlin")] && declaration.name == builtinNames.unit
            if isUnitObject {
                types.unitClassSymbol = symbol
            }
            // Unit's value representation is a builtin type, but its member
            // declarations are source-backed. Use the builtin type as the
            // member receiver so normal overload resolution accepts Unit
            // values without a name-based dispatch exception.
            let objectType = isUnitObject
                ? unitType
                : types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            let objectScope = ClassMemberScope(
                parent: scope,
                symbols: symbols,
                ownerSymbol: symbol,
                thisType: objectType
            )
            collectNestedTypeAliases(
                objectDecl.nestedTypeAliases,
                ownerFQName: fqName,
                sourceFileID: file.fileID,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
            collectMemberHeaders(
                members: MemberDeclarations(
                    functions: objectDecl.memberFunctions,
                    properties: objectDecl.memberProperties,
                    nestedClasses: objectDecl.nestedClasses,
                    nestedObjects: objectDecl.nestedObjects
                ),
                owner: OwnerContext(fqName: fqName, symbol: symbol, type: objectType),
                sourceFileID: file.fileID,
                ctx: ctx,
                ast: ast,
                symbols: symbols,
                types: types,
                bindings: bindings,
                scope: objectScope,
                diagnostics: diagnostics,
                interner: interner
            )
            if objectDecl.modifiers.contains(.data) {
                collectSyntheticToString(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: objectType,
                    requireDataTypeFlag: false,
                    symbols: symbols,
                    types: types,
                    scope: objectScope,
                    interner: interner
                )
                collectSyntheticEquals(
                    ownerSymbol: symbol,
                    ownerFQName: fqName,
                    ownerType: objectType,
                    requireDataTypeFlag: false,
                    symbols: symbols,
                    types: types,
                    scope: objectScope,
                    interner: interner
                )
            }

        case let .funDecl(funDecl):
            let localNamespaceFQName = fqName + [interner.intern("$\(symbol.rawValue)")]
            let typeParamResult = collectFunctionTypeParameters(
                funDecl.typeParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner, isInline: funDecl.isInline,
                diagnostics: diagnostics,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports
            )
            let contextReceiverTypes = funDecl.contextReceivers.compactMap { contextReceiver in
                resolveTypeRef(
                    contextReceiver.type,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: typeParamResult.localTypeParameters,
                    relativeOwnerFQName: package,
                    currentPackageFQName: package,
                    imports: file.imports,
                    diagnostics: diagnostics,
                    usageRange: funDecl.range
                )
            }
            let explicitReceiverType = resolveTypeRef(
                funDecl.receiverType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: funDecl.range
            )
            // Top-level context functions use the first context receiver as their
            // hidden receiver parameter in KIR. Member declarations are registered
            // separately and keep the owning class as `receiverType`.
            let receiverType = explicitReceiverType ?? contextReceiverTypes.first
            let params = collectValueParameters(
                funDecl.valueParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: funDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                fallbackType: anyType
            )
            let returnType: TypeID = if let explicit = resolveTypeRef(
                funDecl.returnType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: funDecl.range
            ) {
                explicit
            } else {
                switch funDecl.body {
                case .unit, .block:
                    unitType
                case .expr:
                    anyType
                }
            }
            let upperBoundsByTypeParam: [[TypeID]] = typeParamResult.typeParameterSymbols.map {
                symbols.typeParameterUpperBounds(for: $0)
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    contextReceiverTypes: contextReceiverTypes,
                    parameterTypes: params.paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: params.paramSymbols,
                    valueParameterHasDefaultValues: params.paramHasDefaultValues,
                    valueParameterIsVararg: params.paramIsVararg,
                    valueParameterAllowsNonLocalReturn: params.paramAllowsNonLocalReturn,
                    typeParameterSymbols: typeParamResult.typeParameterSymbols,
                    reifiedTypeParameterIndices: typeParamResult.reifiedIndices,
                    typeParameterUpperBoundsList: upperBoundsByTypeParam
                ),
                for: symbol
            )

            // KSP-INF-011: Attach public/internal top-level extension functions to their
            // receiver nominal type so member-call fallback resolution can find
            // source-backed stdlib replacements (e.g. List<T>.joinToString in
            // StringSplitJoin.kt) even when the declaring package differs from the
            // receiver owner package. Skip private extensions so they retain
            // file-private visibility rather than being gated by the receiver class.
            // Also skip functions whose synthetic runtime stub is intentionally retained
            // as a migration bridge (e.g. List.first), so call sites keep routing
            // through the kk_* ABI entry.
            if declaration.visibility != .private,
               let receiverType,
               let receiverSymbol = BundledDeclarationIndex.receiverOwnerSymbol(
                   for: receiverType,
                   types: types
               ),
               let semanticSymbol = symbols.symbol(symbol),
               let key = BundledDeclarationIndex.memberKey(
                   for: semanticSymbol,
                   symbolID: symbol,
                   symbols: symbols,
                   types: types,
                   interner: interner
               ),
               !BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap(key, interner: interner) {
                symbols.setParentSymbol(receiverSymbol, for: symbol)

                // KSP-443: Runtime-linked bundled extension functions are registered
                // under their declaring package FQ, but synthetic-member-link tests
                // and surface-spec checks resolve by owner + member name. Create a
                // synthetic member alias under the receiver class FQ that reuses the
                // same signature and externalLinkName, so lookups like
                // kotlin.sequences.Sequence.toHashSet resolve to kk_sequence_toHashSet.
                if let externalLinkName = symbols.externalLinkName(for: symbol),
                   !externalLinkName.isEmpty,
                   let ownerSymbol = symbols.symbol(receiverSymbol),
                   let signature = symbols.functionSignature(for: symbol) {
                    let memberFQName = ownerSymbol.fqName + [semanticSymbol.name]
                    let alreadyExists = symbols.lookupAll(fqName: memberFQName).contains { existingID in
                        guard existingID != symbol,
                              let existingSig = symbols.functionSignature(for: existingID),
                              symbols.parentSymbol(for: existingID) == receiverSymbol
                        else {
                            return false
                        }
                        return existingSig == signature
                    }
                    if !alreadyExists {
                        var aliasFlags = semanticSymbol.flags
                        aliasFlags.insert(.synthetic)
                        aliasFlags.insert(.extensionMemberAlias)
                        let aliasSymbol = symbols.define(
                            kind: .function,
                            name: semanticSymbol.name,
                            fqName: memberFQName,
                            declSite: nil,
                            visibility: semanticSymbol.visibility,
                            flags: aliasFlags
                        )
                        symbols.setParentSymbol(receiverSymbol, for: aliasSymbol)
                        symbols.setFunctionSignature(signature, for: aliasSymbol)
                        symbols.setExternalLinkName(externalLinkName, for: aliasSymbol)
                    }
                }
            }

            checkAndReportJVMErasedCallableConflict(
                for: symbol,
                fqName: fqName,
                range: funDecl.range,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics
            )

        case let .propertyDecl(propertyDecl):
            let typeParamResult = collectFunctionTypeParameters(
                propertyDecl.typeParams,
                localNamespaceFQName: fqName + [interner.intern("$\(symbol.rawValue)")],
                declSite: propertyDecl.range,
                ast: ast, symbols: symbols, types: types,
                interner: interner, isInline: propertyDecl.allAccessorsAreInline,
                diagnostics: diagnostics,
                relativeOwnerFQName: package, currentPackageFQName: package,
                imports: file.imports
            )
            let upperBounds = typeParamResult.typeParameterSymbols.map {
                symbols.typeParameterUpperBounds(for: $0)
            }
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: propertyDecl.range
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: symbol)

            if let getter = propertyDecl.getter, getter.body != .unit {
                symbols.setPropertyHasCustomGetter(true, for: symbol)
            }

            if let receiverType = resolveTypeRef(
                propertyDecl.receiverType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: typeParamResult.localTypeParameters,
                relativeOwnerFQName: package,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: propertyDecl.range
            ) {
                symbols.setExtensionPropertyReceiverType(receiverType, for: symbol)

                let getterSymbol = symbols.define(
                    kind: .function,
                    name: interner.intern("get"),
                    fqName: fqName + [interner.intern("$get")],
                    declSite: propertyDecl.range,
                    visibility: visibility(from: propertyDecl.modifiers),
                    flags: [.synthetic]
                )
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: resolvedType,
                        typeParameterSymbols: typeParamResult.typeParameterSymbols,
                        reifiedTypeParameterIndices: typeParamResult.reifiedIndices,
                        typeParameterUpperBoundsList: upperBounds
                    ),
                    for: getterSymbol
                )
                symbols.setParentSymbol(symbol, for: getterSymbol)
                symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: symbol)

                if propertyDecl.isVar {
                    let setterSymbol = symbols.define(
                        kind: .function,
                        name: interner.intern("set"),
                        fqName: fqName + [interner.intern("$set")],
                        declSite: propertyDecl.range,
                        visibility: visibility(from: propertyDecl.modifiers),
                        flags: [.synthetic]
                    )
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: receiverType,
                            parameterTypes: [resolvedType],
                            returnType: unitType,
                            typeParameterSymbols: typeParamResult.typeParameterSymbols,
                            reifiedTypeParameterIndices: typeParamResult.reifiedIndices,
                            typeParameterUpperBoundsList: upperBounds
                        ),
                        for: setterSymbol
                    )
                    symbols.setParentSymbol(symbol, for: setterSymbol)
                    symbols.setExtensionPropertySetterAccessor(setterSymbol, for: symbol)
                }
            }

            // Materialize a backing field symbol for top-level properties with
            // custom accessors or explicit backing field declarations
            // (mirrors member property backing field logic).
            // Simple properties with only an initializer don't need a separate
            // backing field — the property symbol IS the storage.
            // Getter-only computed properties never need a backing field.
            let hasExplicitBackingField = propertyDecl.explicitBackingField != nil
            let isGetterOnlyComputed = propertyDecl.getter != nil
                && propertyDecl.setter == nil
                && propertyDecl.initializer == nil
                && !hasExplicitBackingField
            let needsBackingField = hasExplicitBackingField
                || (!isGetterOnlyComputed
                    && (propertyDecl.getter != nil || propertyDecl.setter != nil))
            if needsBackingField, propertyDecl.delegateExpression == nil, propertyDecl.receiverType == nil {
                let fieldName = interner.intern("$backing_\(interner.resolve(propertyDecl.name))")
                let fieldFQName = fqName.dropLast() + [fieldName]
                let backingFieldSymbol = symbols.define(
                    kind: .backingField,
                    name: fieldName,
                    fqName: Array(fieldFQName),
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: propertyDecl.isVar ? [.mutable] : []
                )
                // When an explicit backing field declares its own type, use that
                // type for the backing field symbol instead of the property type.
                let backingFieldType: TypeID
                if let explicitField = propertyDecl.explicitBackingField,
                   let explicitType = explicitField.type
                {
                    backingFieldType = resolveTypeRef(
                        explicitType,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        localTypeParameters: [:],
                        relativeOwnerFQName: package,
                        currentPackageFQName: package,
                        imports: file.imports,
                        diagnostics: diagnostics,
                        usageRange: propertyDecl.range
                    ) ?? resolvedType
                } else {
                    backingFieldType = resolvedType
                }
                symbols.setPropertyType(backingFieldType, for: backingFieldSymbol)
                symbols.setBackingFieldSymbol(backingFieldSymbol, for: symbol)
            }

            validateConstPropertyDeclaration(
                propertyDecl,
                propertySymbol: symbol,
                resolvedType: resolvedType,
                ast: ast,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )

        case let .typeAliasDecl(typeAliasDecl):
            let localTypeParameters = registerTypeAliasTypeParameters(
                typeAliasDecl.typeParams,
                aliasSymbol: symbol,
                parentFQName: fqName,
                declSite: typeAliasDecl.range,
                symbols: symbols,
                interner: interner
            )
            if typeAliasDecl.underlyingType == nil {
                diagnostics.error(
                    "KSWIFTK-SEMA-0061",
                    "Type alias '\(interner.resolve(typeAliasDecl.name))' must have a right-hand side type.",
                    range: typeAliasDecl.range
                )
            } else if let resolvedUnderlying = resolveTypeRef(
                typeAliasDecl.underlyingType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters,
                currentPackageFQName: package,
                imports: file.imports,
                diagnostics: diagnostics,
                usageRange: typeAliasDecl.range
            ) {
                symbols.setTypeAliasUnderlyingType(resolvedUnderlying, for: symbol)
            }

        case .enumEntryDecl:
            break
        }
    }
}
