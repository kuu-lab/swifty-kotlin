/// kotlinc `kotlinx.serialization` compiler plugin equivalent.
/// Classes annotated with `@Serializable` (`kotlinx.serialization.Serializable`)
/// gain synthetic serialization support:
///   - An automatic companion object (if none exists)
///   - A synthetic `serializer()` function on the companion object returning `KSerializer<T>`
///   - A synthetic nested `$serializer` class implementing `KSerializer<T>`
///
/// Configuration:
///   -P plugin:org.jetbrains.kotlinx.serialization:additionalAnnotation=<fqName>  (repeatable)
///
/// Validation rules matching kotlinc:
///   - Target must be a class or object. Annotating interfaces or annotation classes
///     emits `KSWIFTK-SEMA-0487` ('@Serializable' annotation is only supported for classes and objects).
///   - Inner classes are not supported and emit `KSWIFTK-SEMA-0488` ('@Serializable' annotation is not supported for inner classes).
struct KotlinxSerializationPlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlinx.serialization"

    private let defaultTriggers: Set<String> = [
        "kotlinx.serialization.Serializable",
    ]

    func applyPostInheritanceSemaTransform(_ context: CompilerPluginSemaContext) {
        var triggers = defaultTriggers
        let additional = context.pluginConfig.optionValues(for: id, key: "additionalAnnotation")
        for ann in additional {
            triggers.insert(ann)
        }

        let symbols = context.symbols

        for symbol in symbols.allSymbols() {
            guard !symbol.flags.contains(.importedLibrary),
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.precomputedStdlibSynthetic),
                  hasTriggerAnnotation(symbol.id, triggers: triggers, symbols: symbols)
            else { continue }

            // 1. Kind check: class or object only
            if symbol.kind != .class && symbol.kind != .object {
                context.diagnostics.error(
                    "KSWIFTK-SEMA-0487",
                    "'@Serializable' annotation is only supported for classes and objects.",
                    range: symbol.declSite
                )
                continue
            }

            // 2. Inner class check
            if symbol.flags.contains(.innerClass) {
                context.diagnostics.error(
                    "KSWIFTK-SEMA-0488",
                    "'@Serializable' annotation is not supported for inner classes.",
                    range: symbol.declSite
                )
                continue
            }

            // 3. Generate serialization members
            Self.synthesizeSerializationMembers(
                for: symbol,
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

    static func synthesizeSerializationMembers(
        for classSymbol: SemanticSymbol,
        context: CompilerPluginSemaContext
    ) {
        if context.sema.serializationClasses[classSymbol.id] != nil {
            return
        }
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let classID = classSymbol.id

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

        // 1. Find or synthesize companion object
        let companionName = interner.intern("Companion")
        var companionSymbol: SymbolID? = symbols.companionObjectSymbol(for: classID)

        if companionSymbol == nil {
            let compSym = symbols.define(
                kind: .object,
                name: companionName,
                fqName: classSymbol.fqName + [companionName],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classID, for: compSym)
            symbols.setCompanionObjectSymbol(compSym, for: classID)
            companionSymbol = compSym
        }

        guard let compID = companionSymbol, let compSym = symbols.symbol(compID) else { return }

        let compType = types.make(.classType(ClassType(
            classSymbol: compID,
            args: [],
            enclosingTypeArgs: [],
            nullability: .nonNull
        )))

        // 2. Synthesize serializer() on the companion object (if not already declared)
        let serializerName = interner.intern("serializer")
        var companionSerializerSymbol: SymbolID? = nil

        let existingSerializer = symbols.lookupAll(
            fqName: compSym.fqName + [serializerName]
        ).filter {
            symbols.symbol($0)?.kind == .function
                && symbols.parentSymbol(for: $0) == compID
        }

        if existingSerializer.isEmpty {
            let serializerSym = symbols.define(
                kind: .function,
                name: serializerName,
                fqName: compSym.fqName + [serializerName],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(compID, for: serializerSym)

            let returnType = resolveKSerializerType(
                for: classType,
                symbols: symbols,
                types: types,
                interner: interner
            )

            // For generic classes, serializer() takes KSerializer<T> for each type parameter
            var paramTypes: [TypeID] = []
            var valueParamSymbols: [SymbolID] = []
            for (idx, tpSym) in ownTypeParams.enumerated() {
                let pName = interner.intern("typeSerial\(idx)")
                let pSym = symbols.define(
                    kind: .valueParameter,
                    name: pName,
                    fqName: compSym.fqName + [serializerName, pName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(serializerSym, for: pSym)
                valueParamSymbols.append(pSym)

                let tpType = types.make(.typeParam(TypeParamType(symbol: tpSym)))
                let serializerArgType = resolveKSerializerType(
                    for: tpType,
                    symbols: symbols,
                    types: types,
                    interner: interner
                )
                paramTypes.append(serializerArgType)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: compType,
                    parameterTypes: paramTypes,
                    returnType: returnType,
                    valueParameterSymbols: valueParamSymbols,
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: serializerSym
            )
            companionSerializerSymbol = serializerSym
        }

        // 3. Synthesize nested $serializer class
        let genSerializerName = interner.intern("$serializer")
        let genSerializerFQName = classSymbol.fqName + [genSerializerName]
        var generatedSerializerClassSymbol: SymbolID? = symbols.lookup(fqName: genSerializerFQName)

        if generatedSerializerClassSymbol == nil {
            let genSym = symbols.define(
                kind: .class,
                name: genSerializerName,
                fqName: genSerializerFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classID, for: genSym)

            let genType = types.make(.classType(ClassType(
                classSymbol: genSym,
                args: selfArgs.own,
                enclosingTypeArgs: selfArgs.enclosing,
                nullability: .nonNull
            )))

            // Synthesize parameterless constructor for $serializer
            let initName = interner.intern("<init>")
            let ctorSym = symbols.define(
                kind: .constructor,
                name: genSerializerName,
                fqName: genSerializerFQName + [initName],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(genSym, for: ctorSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: genType,
                    parameterTypes: [],
                    returnType: genType,
                    valueParameterSymbols: [],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: ctorSym
            )

            generatedSerializerClassSymbol = genSym
        }

        context.sema.serializationClasses[classID] = SerializationClassInfo(
            companionSerializerMethod: companionSerializerSymbol,
            generatedSerializerClass: generatedSerializerClassSymbol,
            companionObjectSymbol: compID
        )
    }

    private static func resolveKSerializerType(
        for classType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kSerializerFQName = [
            interner.intern("kotlinx"),
            interner.intern("serialization"),
            interner.intern("KSerializer"),
        ]
        if let kSerializerSym = symbols.lookup(fqName: kSerializerFQName) {
            return types.make(.classType(ClassType(
                classSymbol: kSerializerSym,
                args: [.invariant(classType)],
                nullability: .nonNull
            )))
        }
        if let kSerializerSym = symbols.lookup(fqName: [interner.intern("KSerializer")]) {
            return types.make(.classType(ClassType(
                classSymbol: kSerializerSym,
                args: [.invariant(classType)],
                nullability: .nonNull
            )))
        }
        if let kSerializerSym = symbols.lookupByShortName(interner.intern("KSerializer")).first(where: {
            let k = symbols.symbol($0)?.kind
            return k == .interface || k == .class
        }) {
            return types.make(.classType(ClassType(
                classSymbol: kSerializerSym,
                args: [.invariant(classType)],
                nullability: .nonNull
            )))
        }
        return types.anyType
    }
}
