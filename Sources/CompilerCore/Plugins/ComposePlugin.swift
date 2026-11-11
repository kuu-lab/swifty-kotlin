/// Built-in Compose compiler plugin (`androidx.compose.compiler.plugins.kotlin`).
/// Supports `@Composable`, `@ReadOnlyComposable`, `@DisallowComposableCalls`,
/// `@Stable`, and `@Immutable` annotations:
///   - Validates `@Composable` declaration constraints (`suspend`, `main`, `var`/backing fields).
///   - Records `@Composable` functions, getters, and `@Composable` function-type parameters
///     for Sema context verification (`validateComposableContexts`).
///   - Drives `ComposeLoweringPass` to inject `$composer: Composer?` and `$changed: Int`
///     parameters and propagate them across `@Composable` call sites in KIR.
///
/// Configuration (kotlinc / compose-compiler-plugin compatible):
///   -P plugin:androidx.compose.compiler.plugins.kotlin:<option>=<value>
///   -Xplugin=.../compose-compiler-plugin.jar
struct ComposePlugin: CompilerPlugin {
    let id = "androidx.compose.compiler.plugins.kotlin"

    static let composableFQName = "androidx.compose.runtime.Composable"
    static let readonlyComposableFQName = "androidx.compose.runtime.ReadOnlyComposable"
    static let disallowComposableCallsFQName = "androidx.compose.runtime.DisallowComposableCalls"
    static let stableFQName = "androidx.compose.runtime.Stable"
    static let immutableFQName = "androidx.compose.runtime.Immutable"
    static let composerFQName = ["androidx", "compose", "runtime", "Composer"]

    func applySemaTransform(_ context: CompilerPluginSemaContext) {
        let hasConfig = context.pluginConfig.values[id] != nil
        guard hasConfig || hasComposeAnnotations(in: context) else {
            return
        }
        Self.applyCompose(context: context)
    }

    static func applyCompose(context: CompilerPluginSemaContext) {
        guard !context.sema.composePluginEnabled else { return }
        context.sema.composePluginEnabled = true

        let symbols = context.symbols
        let types = context.types
        let interner = context.interner

        let composerFQ = composerFQName.map { interner.intern($0) }
        if let composerSym = symbols.lookup(fqName: composerFQ),
           let symInfo = symbols.symbol(composerSym),
           symInfo.kind == .interface || symInfo.kind == .class
        {
            context.sema.composeComposerSymbol = composerSym
            context.sema.composeComposerType = types.make(.classType(ClassType(
                classSymbol: composerSym,
                args: [],
                nullability: .nullable
            )))
        }

        let hasComposableSym = symbols.lookup(
            fqName: ["androidx", "compose", "runtime", "Composable"].map { interner.intern($0) }
        ) != nil
        let hasReadOnlySym = symbols.lookup(
            fqName: ["androidx", "compose", "runtime", "ReadOnlyComposable"].map { interner.intern($0) }
        ) != nil
        let hasDisallowSym = symbols.lookup(
            fqName: ["androidx", "compose", "runtime", "DisallowComposableCalls"].map { interner.intern($0) }
        ) != nil
        let hasStableSym = symbols.lookup(
            fqName: ["androidx", "compose", "runtime", "Stable"].map { interner.intern($0) }
        ) != nil
        let hasImmutableSym = symbols.lookup(
            fqName: ["androidx", "compose", "runtime", "Immutable"].map { interner.intern($0) }
        ) != nil

        // 1. Scan AST declarations for @Composable functions, properties, parameters, and validation diagnostics.
        for file in context.ast.sortedFiles {
            for declID in file.topLevelDecls {
                scanDeclRecursively(
                    declID: declID,
                    context: context,
                    hasComposableSym: hasComposableSym,
                    hasReadOnlySym: hasReadOnlySym,
                    hasDisallowSym: hasDisallowSym,
                    hasStableSym: hasStableSym,
                    hasImmutableSym: hasImmutableSym
                )
            }
        }

        // 2. Also include any @Composable functions from SymbolTable (e.g. imported libraries).
        for symbol in symbols.allSymbols() where symbol.kind == .function {
            let anns = symbols.annotations(for: symbol.id)
            if anns.contains(where: { isComposableAnnotation($0.annotationFQName, allowShort: hasComposableSym) }) {
                context.sema.composableFunctions.insert(symbol.id)
            }
            if anns.contains(where: { isReadOnlyAnnotation($0.annotationFQName, allowShort: hasReadOnlySym) }) {
                context.sema.readonlyComposableFunctions.insert(symbol.id)
            }
        }
    }

    private func hasComposeAnnotations(in context: CompilerPluginSemaContext) -> Bool {
        let interner = context.interner
        let symbols = context.symbols
        let hasComposableDef = symbols.lookup(
            fqName: ["androidx", "compose", "runtime", "Composable"].map { interner.intern($0) }
        ) != nil

        for symbol in symbols.allSymbols() {
            let anns = symbols.annotations(for: symbol.id)
            if anns.contains(where: {
                Self.isComposableAnnotation($0.annotationFQName, allowShort: hasComposableDef)
                    || Self.isStableAnnotation($0.annotationFQName, allowShort: false)
                    || Self.isImmutableAnnotation($0.annotationFQName, allowShort: false)
            }) {
                return true
            }
        }

        for decl in context.ast.arena.declarations() {
            switch decl {
            case let .funDecl(funDecl):
                if funDecl.annotations.contains(where: {
                    Self.isComposableAnnotation($0.name, allowShort: hasComposableDef)
                }) {
                    return true
                }
                for param in funDecl.valueParams {
                    if let typeRef = param.type,
                       Self.typeRefHasAnnotation(
                           typeRef,
                           arena: context.ast.arena,
                           predicate: { Self.isComposableAnnotation($0.name, allowShort: hasComposableDef) }
                       )
                    {
                        return true
                    }
                }
            case let .propertyDecl(propDecl):
                if propDecl.annotations.contains(where: {
                    Self.isComposableAnnotation($0.name, allowShort: hasComposableDef)
                }) || propDecl.getter?.annotations.contains(where: {
                    Self.isComposableAnnotation($0.name, allowShort: hasComposableDef)
                }) == true {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private static func scanDeclRecursively(
        declID: DeclID,
        context: CompilerPluginSemaContext,
        hasComposableSym: Bool,
        hasReadOnlySym: Bool,
        hasDisallowSym: Bool,
        hasStableSym: Bool,
        hasImmutableSym: Bool
    ) {
        guard let decl = context.ast.arena.decl(declID) else { return }
        let symbols = context.symbols
        let symID = context.bindings.declSymbols[declID]

        switch decl {
        case let .classDecl(classDecl):
            if let symID {
                let symAnns = symbols.annotations(for: symID).map(\.annotationFQName)
                if classDecl.annotations.contains(where: {
                    isStableAnnotation($0.name, allowShort: hasStableSym)
                        || isImmutableAnnotation($0.name, allowShort: hasImmutableSym)
                }) || symAnns.contains(where: {
                    isStableAnnotation($0, allowShort: hasStableSym)
                        || isImmutableAnnotation($0, allowShort: hasImmutableSym)
                }) {
                    context.sema.stableAnnotatedSymbols.insert(symID)
                }
            }
            for childDecl in classDecl.memberFunctions + classDecl.memberProperties + classDecl.nestedClasses + classDecl.nestedObjects {
                scanDeclRecursively(
                    declID: childDecl,
                    context: context,
                    hasComposableSym: hasComposableSym,
                    hasReadOnlySym: hasReadOnlySym,
                    hasDisallowSym: hasDisallowSym,
                    hasStableSym: hasStableSym,
                    hasImmutableSym: hasImmutableSym
                )
            }

        case let .interfaceDecl(interfaceDecl):
            for childDecl in interfaceDecl.memberFunctions + interfaceDecl.memberProperties + interfaceDecl.nestedClasses + interfaceDecl.nestedObjects {
                scanDeclRecursively(
                    declID: childDecl,
                    context: context,
                    hasComposableSym: hasComposableSym,
                    hasReadOnlySym: hasReadOnlySym,
                    hasDisallowSym: hasDisallowSym,
                    hasStableSym: hasStableSym,
                    hasImmutableSym: hasImmutableSym
                )
            }

        case let .objectDecl(objectDecl):
            for childDecl in objectDecl.memberFunctions + objectDecl.memberProperties + objectDecl.nestedClasses + objectDecl.nestedObjects {
                scanDeclRecursively(
                    declID: childDecl,
                    context: context,
                    hasComposableSym: hasComposableSym,
                    hasReadOnlySym: hasReadOnlySym,
                    hasDisallowSym: hasDisallowSym,
                    hasStableSym: hasStableSym,
                    hasImmutableSym: hasImmutableSym
                )
            }

        case let .funDecl(funDecl):
            guard let symID else { return }
            let symAnns = symbols.annotations(for: symID).map(\.annotationFQName)
            let isComposable = funDecl.annotations.contains(where: { isComposableAnnotation($0.name, allowShort: hasComposableSym) })
                || symAnns.contains(where: { isComposableAnnotation($0, allowShort: hasComposableSym) })
            let isReadOnly = funDecl.annotations.contains(where: { isReadOnlyAnnotation($0.name, allowShort: hasReadOnlySym) })
                || symAnns.contains(where: { isReadOnlyAnnotation($0, allowShort: hasReadOnlySym) })

            if isComposable {
                if funDecl.isSuspend {
                    context.diagnostics.error(
                        "KSWIFTK-SEMA-0490",
                        "Composable functions cannot be suspend functions.",
                        range: funDecl.range
                    )
                }
                let parentKind = symbols.parentSymbol(for: symID).flatMap { symbols.symbol($0)?.kind }
                let isTopLevel = parentKind == nil || parentKind == .package
                if !funDecl.isScriptEntryPoint,
                   isTopLevel,
                   context.interner.resolve(funDecl.name) == "main"
                {
                    context.diagnostics.error(
                        "KSWIFTK-SEMA-0491",
                        "Composable functions cannot be 'main' entry points.",
                        range: funDecl.range
                    )
                }
                context.sema.composableFunctions.insert(symID)
                if isReadOnly {
                    context.sema.readonlyComposableFunctions.insert(symID)
                }
            }

            if let sig = symbols.functionSignature(for: symID) {
                for (index, param) in funDecl.valueParams.enumerated() where sig.valueParameterSymbols.indices.contains(index) {
                    let paramSym = sig.valueParameterSymbols[index]
                    let paramSymAnns = symbols.annotations(for: paramSym).map(\.annotationFQName)
                    if let typeRef = param.type,
                       typeRefHasAnnotation(
                           typeRef,
                           arena: context.ast.arena,
                           predicate: { isComposableAnnotation($0.name, allowShort: hasComposableSym) }
                       )
                    {
                        context.sema.composableFunctionParameters.insert(paramSym)
                    }
                    let disallowOnParam = param.annotations.contains(where: { isDisallowAnnotation($0.name, allowShort: hasDisallowSym) })
                        || paramSymAnns.contains(where: { isDisallowAnnotation($0, allowShort: hasDisallowSym) })
                        || (param.type.map {
                            typeRefHasAnnotation(
                                $0,
                                arena: context.ast.arena,
                                predicate: { isDisallowAnnotation($0.name, allowShort: hasDisallowSym) }
                            )
                        } ?? false)
                    if disallowOnParam {
                        context.sema.disallowComposableCallsParameters.insert(paramSym)
                    }
                }
            }

        case let .propertyDecl(propDecl):
            guard let symID else { return }
            let symAnns = symbols.annotations(for: symID).map(\.annotationFQName)
            let propComposable = propDecl.annotations.contains(where: { isComposableAnnotation($0.name, allowShort: hasComposableSym) })
                || symAnns.contains(where: { isComposableAnnotation($0, allowShort: hasComposableSym) })
            let getterComposable = propDecl.getter?.annotations.contains(where: { isComposableAnnotation($0.name, allowShort: hasComposableSym) }) == true
            let isReadOnly = propDecl.annotations.contains(where: { isReadOnlyAnnotation($0.name, allowShort: hasReadOnlySym) })
                || propDecl.getter?.annotations.contains(where: { isReadOnlyAnnotation($0.name, allowShort: hasReadOnlySym) }) == true
                || symAnns.contains(where: { isReadOnlyAnnotation($0, allowShort: hasReadOnlySym) })

            if propComposable || getterComposable {
                if propDecl.isVar {
                    context.diagnostics.error(
                        "KSWIFTK-SEMA-0492",
                        "Mutable 'var' properties cannot be @Composable.",
                        range: propDecl.range
                    )
                } else if propDecl.initializer != nil || propDecl.delegateExpression != nil {
                    context.diagnostics.error(
                        "KSWIFTK-SEMA-0492",
                        "@Composable properties cannot have backing fields.",
                        range: propDecl.range
                    )
                }
                context.sema.composableFunctions.insert(symID)
                let syntheticGetter = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symID)
                context.sema.composableFunctions.insert(syntheticGetter)
                if let extGetter = symbols.extensionPropertyGetterAccessor(for: symID) {
                    context.sema.composableFunctions.insert(extGetter)
                }
                if isReadOnly {
                    context.sema.readonlyComposableFunctions.insert(symID)
                    context.sema.readonlyComposableFunctions.insert(syntheticGetter)
                    if let extGetter = symbols.extensionPropertyGetterAccessor(for: symID) {
                        context.sema.readonlyComposableFunctions.insert(extGetter)
                    }
                }
            }

        default:
            break
        }
    }

    static func typeRefHasAnnotation(
        _ typeRefID: TypeRefID,
        arena: ASTArena,
        predicate: (AnnotationNode) -> Bool
    ) -> Bool {
        guard let typeRef = arena.typeRef(typeRefID) else { return false }
        switch typeRef {
        case let .annotated(base, annotations):
            if annotations.contains(where: predicate) {
                return true
            }
            return typeRefHasAnnotation(base, arena: arena, predicate: predicate)
        case .named, .functionType, .intersection:
            return false
        }
    }

    static func isComposableAnnotation(_ name: String, allowShort: Bool) -> Bool {
        name == composableFQName || (allowShort && name == "Composable")
    }

    static func isReadOnlyAnnotation(_ name: String, allowShort: Bool) -> Bool {
        name == readonlyComposableFQName || (allowShort && name == "ReadOnlyComposable")
    }

    static func isDisallowAnnotation(_ name: String, allowShort: Bool) -> Bool {
        name == disallowComposableCallsFQName || (allowShort && name == "DisallowComposableCalls")
    }

    static func isStableAnnotation(_ name: String, allowShort: Bool) -> Bool {
        name == stableFQName || (allowShort && name == "Stable")
    }

    static func isImmutableAnnotation(_ name: String, allowShort: Bool) -> Bool {
        name == immutableFQName || (allowShort && name == "Immutable")
    }
}
