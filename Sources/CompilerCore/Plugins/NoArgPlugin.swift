/// kotlinc `kotlin-noarg` equivalent. Classes annotated with a configured
/// annotation gain a synthetic public zero-argument constructor that
/// delegates only to the superclass constructor — property initializers and
/// `init` blocks do not run unless `invokeInitializers` is enabled, so
/// fields keep their JVM-default values. Frameworks (JPA, Android) reach it
/// through reflection; the constructor is marked `@Deprecated(HIDDEN)` so
/// Kotlin call resolution cannot select it, matching kotlinc.
///
/// Configuration:
///   -P plugin:org.jetbrains.kotlin.noarg:annotation=<fqName>   (repeatable)
///   -P plugin:org.jetbrains.kotlin.noarg:invokeInitializers=true
///
/// The plugin only synthesizes constructors for source declarations in the
/// current module. Classes that already expose a zero-argument call — an
/// explicit `constructor()`, an implicit primary with no parameters, or a
/// primary whose parameters all have defaults (covered by the built-in
/// all-defaults no-arg constructor) — are skipped, mirroring kotlinc.
struct NoArgPlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlin.noarg"

    /// Runs post-inheritance: the superclass zero-argument constructor check
    /// needs `directSupertypes`, which `bindInheritanceEdges` only populates
    /// after the pre-inheritance plugin hook.
    func applyPostInheritanceSemaTransform(_ context: CompilerPluginSemaContext) {
        let triggers = Set(context.pluginConfig.optionValues(for: id, key: "annotation"))
        guard !triggers.isEmpty else { return }
        let runsInitializers = context.pluginConfig
            .optionValues(for: id, key: "invokeInitializers")
            .contains { $0 == "true" }
        let symbols = context.symbols
        let interner = context.interner
        let initName = interner.intern("<init>")
        for symbol in symbols.allSymbols() {
            guard symbol.kind == .class,
                  !symbol.flags.contains(.importedLibrary),
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.precomputedStdlibSynthetic),
                  !symbol.flags.contains(.innerClass),
                  !symbol.flags.contains(.expectDeclaration),
                  !symbol.flags.contains(.valueType),
                  hasTriggerAnnotation(symbol.id, triggers: triggers, symbols: symbols)
            else { continue }
            generateNoArgConstructor(
                for: symbol,
                runsInitializers: runsInitializers,
                initName: initName,
                context: context
            )
        }
    }

    private func hasTriggerAnnotation(
        _ symbolID: SymbolID,
        triggers: Set<String>,
        symbols: SymbolTable
    ) -> Bool {
        symbols.annotations(for: symbolID).contains { triggers.contains($0.annotationFQName) }
    }

    private func generateNoArgConstructor(
        for classSymbol: SemanticSymbol,
        runsInitializers: Bool,
        initName: InternedString,
        context: CompilerPluginSemaContext
    ) {
        let symbols = context.symbols
        let types = context.types
        let classID = classSymbol.id
        let ctorFQName = classSymbol.fqName + [initName]

        let existingCtors = symbols.lookupAll(fqName: ctorFQName).filter {
            symbols.symbol($0)?.kind == .constructor
                && symbols.parentSymbol(for: $0) == classID
        }
        var primaryHasAllDefaults = false
        for ctor in existingCtors {
            guard let signature = symbols.functionSignature(for: ctor) else { continue }
            // An existing zero-parameter constructor — explicit `constructor()`
            // or an implicit primary on a parameterless class — already
            // provides `<init>()V`; generating another would duplicate it.
            if signature.parameterTypes.isEmpty { return }
            // The primary constructor's declSite is the class range. When all
            // of its parameters default, the compiler already synthesizes the
            // Java-visible no-arg constructor with full initialization, which
            // is what kotlinc keeps instead of the plugin's super-only one.
            // `valueParameterHasDefaultValues` may be shorter than the
            // parameter list; a missing flag means "no default".
            let allParametersDefaulted = signature.parameterTypes.indices.allSatisfy {
                signature.valueParameterHasDefaultValues.indices.contains($0)
                    && signature.valueParameterHasDefaultValues[$0]
            }
            if symbols.symbol(ctor)?.declSite == classSymbol.declSite,
               allParametersDefaulted
            {
                primaryHasAllDefaults = true
            }
        }
        if primaryHasAllDefaults { return }

        // Resolve the super constructor a bare `super()` call would select:
        // an exact no-arg overload wins, otherwise an all-default overload
        // (fewest parameters first, matching overload-resolution preference).
        var superCtor: SymbolID? = nil
        var supertypeTypeArguments: [TypeArg] = []
        if let edgeSupertype = symbols.directSupertypes(for: classID).first(where: {
            let kind = symbols.symbol($0)?.kind
            return kind == .class || kind == .enumClass
        }) {
            // Expect edges key `supertypeTypeArgs` under the expect symbol;
            // the constructor lives on the linked actual declaration.
            var superclassSymbol = edgeSupertype
            if let actual = symbols.actualSymbol(for: edgeSupertype),
               let edgeKind = symbols.symbol(edgeSupertype)?.kind,
               symbols.symbol(actual)?.kind == edgeKind
            {
                superclassSymbol = actual
            }
            supertypeTypeArguments = symbols.supertypeTypeArgs(
                for: classID, supertype: edgeSupertype
            )
            if supertypeTypeArguments.isEmpty {
                supertypeTypeArguments = symbols.supertypeTypeArgs(
                    for: classID, supertype: superclassSymbol
                )
            }
            if let superclassInfo = symbols.symbol(superclassSymbol) {
                let candidates = symbols.lookupAll(
                    fqName: superclassInfo.fqName + [initName]
                ).filter {
                    symbols.symbol($0)?.kind == .constructor
                        && symbols.parentSymbol(for: $0) == superclassSymbol
                }
                let applicable = candidates.filter { ctor in
                    guard let signature = symbols.functionSignature(for: ctor) else { return false }
                    if signature.parameterTypes.isEmpty { return true }
                    return signature.parameterTypes.indices.allSatisfy {
                        signature.valueParameterHasDefaultValues.indices.contains($0)
                            && signature.valueParameterHasDefaultValues[$0]
                    }
                }
                superCtor = applicable.min { lhs, rhs in
                    let l = symbols.functionSignature(for: lhs)?.parameterTypes.count ?? .max
                    let r = symbols.functionSignature(for: rhs)?.parameterTypes.count ?? .max
                    return l < r
                }
            }
            if superCtor == nil, symbols.symbol(superclassSymbol)?.kind != .enumClass {
                context.diagnostics.error(
                    "KSWIFTK-SEMA-0483",
                    "zero-argument constructor was not found in the superclass.",
                    range: classSymbol.declSite
                )
                return
            }
        }

        let ownTypeParams = types.nominalTypeParameterSymbols(for: classID)
        let enclosingTypeParams = types.enclosingTypeParameterSymbols(for: classID)
        let typeParamSymbols = enclosingTypeParams + ownTypeParams
        let selfArgs: (own: [TypeArg], enclosing: [TypeArg]) = (
            own: ownTypeParams.map {
                .invariant(types.make(.typeParam(TypeParamType(symbol: $0))))
            },
            enclosing: enclosingTypeParams.map {
                .invariant(types.make(.typeParam(TypeParamType(symbol: $0))))
            }
        )
        let classType = types.make(.classType(ClassType(
            classSymbol: classID,
            args: selfArgs.own,
            enclosingTypeArgs: selfArgs.enclosing,
            nullability: .nonNull
        )))

        // kotlinc always emits the generated constructor as public, even when
        // the primary constructor is private — frameworks instantiate it
        // reflectively.
        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: classSymbol.name,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(classID, for: ctorSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: classType,
                parameterTypes: [],
                returnType: classType,
                valueParameterSymbols: [],
                typeParameterSymbols: typeParamSymbols,
                classTypeParameterCount: typeParamSymbols.count
            ),
            for: ctorSymbol
        )
        if let superCtor {
            // The bare `super()` call instantiates the superclass with the
            // type arguments written on the class's supertype edge, so the
            // callee's class type parameters substitute from
            // `supertypeTypeArgs` — the same source
            // `constructorSuperclassType` uses for secondary `super(...)`.
            let substitutedTypeArguments = supertypeTypeArguments.map { arg -> TypeID in
                switch arg {
                case let .invariant(type), let .in(type), let .out(type):
                    return type
                case .star:
                    return types.anyType
                }
            }
            context.bindings.bindConstructorDelegationCall(
                ctorSymbol,
                binding: CallBinding(
                    chosenCallee: superCtor,
                    substitutedTypeArguments: substitutedTypeArguments,
                    parameterMapping: [:]
                )
            )
        }
        // HIDDEN deprecation keeps the constructor out of Kotlin overload
        // resolution while Java/reflection can still reach it — the same
        // role `@Deprecated(HIDDEN)` plays on kotlinc's no-arg output.
        symbols.setAnnotations(
            [MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["level=HIDDEN"]
            )],
            for: ctorSymbol
        )
        context.sema.pluginGeneratedConstructors[ctorSymbol] = PluginGeneratedConstructorInfo(
            runsInitializers: runsInitializers
        )
    }
}
