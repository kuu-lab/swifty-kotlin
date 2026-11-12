/// kotlinc `kotlinx.serialization` compiler plugin equivalent.
/// Classes, objects, and enums annotated with `@Serializable`
/// (`kotlinx.serialization.Serializable`) gain synthetic serialization support:
///   - An automatic companion object (if none exists)
///   - A synthetic `serializer()` function on the companion object returning `KSerializer<T>`
///   - For classes and objects, a synthetic nested `$serializer` class implementing `KSerializer<T>`
///
/// Configuration:
///   -P plugin:org.jetbrains.kotlinx.serialization:additionalAnnotation=<fqName>  (repeatable)
///
/// Validation rules matching kotlinc:
///   - Target must be a class, object, or enum. Annotating interfaces or annotation classes
///     emits `KSWIFTK-SEMA-0487` ('@Serializable' annotation is only supported for classes, objects, and enums).
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

            // 1. Kind check: classes, objects, and enums can carry serializers.
            let isSupportedKind = symbol.kind == .class || symbol.kind == .object || symbol.kind == .enumClass
            if !isSupportedKind {
                context.diagnostics.error(
                    "KSWIFTK-SEMA-0487",
                    "'@Serializable' annotation is only supported for classes, objects, and enums.",
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

        if classSymbol.kind == .enumClass {
            Self.synthesizeEnumSerializer(
                for: classSymbol,
                classType: classType,
                context: context
            )
            return
        }

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

        // 2. For classes and objects, synthesize a nested $serializer class.
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

            // Attach KSerializer<T> supertype to $serializer
            if let kSerializerSym = resolveKSerializerSymbol(symbols: symbols, interner: interner) {
                symbols.setDirectSupertypes([kSerializerSym], for: genSym)
                symbols.setSupertypeTypeArgs([.invariant(classType)], for: genSym, supertype: kSerializerSym)
            }

            let serialDescriptorType = resolveSerializationType(
                fqName: ["kotlinx", "serialization", "descriptors", "SerialDescriptor"],
                shortName: "SerialDescriptor",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let encoderType = resolveSerializationType(
                fqName: ["kotlinx", "serialization", "encoding", "Encoder"],
                shortName: "Encoder",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let decoderType = resolveSerializationType(
                fqName: ["kotlinx", "serialization", "encoding", "Decoder"],
                shortName: "Decoder",
                symbols: symbols,
                types: types,
                interner: interner
            )

            // Synthesize override val descriptor: SerialDescriptor + getter
            let descName = interner.intern("descriptor")
            let descPropSym = symbols.define(
                kind: .property,
                name: descName,
                fqName: genSerializerFQName + [descName],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .overrideMember]
            )
            symbols.setParentSymbol(genSym, for: descPropSym)
            symbols.setPropertyType(serialDescriptorType, for: descPropSym)

            let descGetterSym = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: descPropSym)
            symbols.setExtensionPropertyGetterAccessor(descGetterSym, for: descPropSym)
            symbols.setAccessorOwnerProperty(descPropSym, for: descGetterSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: genType,
                    parameterTypes: [],
                    returnType: serialDescriptorType,
                    valueParameterSymbols: [],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: descGetterSym
            )

            // Synthesize override fun serialize(encoder: Encoder, value: T): Unit
            let serializeName = interner.intern("serialize")
            let serializeFQ = genSerializerFQName + [serializeName]
            let serializeSym = symbols.define(
                kind: .function,
                name: serializeName,
                fqName: serializeFQ,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .overrideMember]
            )
            symbols.setParentSymbol(genSym, for: serializeSym)
            let encParamName = interner.intern("encoder")
            let encParamSym = symbols.define(
                kind: .valueParameter,
                name: encParamName,
                fqName: serializeFQ + [encParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(serializeSym, for: encParamSym)
            let valParamName = interner.intern("value")
            let valParamSym = symbols.define(
                kind: .valueParameter,
                name: valParamName,
                fqName: serializeFQ + [valParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(serializeSym, for: valParamSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: genType,
                    parameterTypes: [encoderType, classType],
                    returnType: types.unitType,
                    valueParameterSymbols: [encParamSym, valParamSym],
                    valueParameterHasDefaultValues: [false, false],
                    valueParameterIsVararg: [false, false],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: serializeSym
            )

            // Synthesize override fun deserialize(decoder: Decoder): T
            let deserializeName = interner.intern("deserialize")
            let deserializeFQ = genSerializerFQName + [deserializeName]
            let deserializeSym = symbols.define(
                kind: .function,
                name: deserializeName,
                fqName: deserializeFQ,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .overrideMember]
            )
            symbols.setParentSymbol(genSym, for: deserializeSym)
            let decParamName = interner.intern("decoder")
            let decParamSym = symbols.define(
                kind: .valueParameter,
                name: decParamName,
                fqName: deserializeFQ + [decParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(deserializeSym, for: decParamSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: genType,
                    parameterTypes: [decoderType],
                    returnType: classType,
                    valueParameterSymbols: [decParamSym],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: deserializeSym
            )

            generatedSerializerClassSymbol = genSym

            let serializableProps = collectSerializableProperties(
                for: classID,
                symbols: symbols,
                interner: interner
            )

            context.sema.serializationClasses[classID] = SerializationClassInfo(
                companionSerializerMethod: companionSerializerSymbol,
                generatedSerializerClass: generatedSerializerClassSymbol,
                companionObjectSymbol: compID,
                serializerConstructor: ctorSym,
                descriptorProperty: descPropSym,
                descriptorGetter: descGetterSym,
                serializeMethod: serializeSym,
                deserializeMethod: deserializeSym,
                serializableProperties: serializableProps
            )
            return
        }

        let serializableProps = collectSerializableProperties(
            for: classID,
            symbols: symbols,
            interner: interner
        )

        context.sema.serializationClasses[classID] = SerializationClassInfo(
            companionSerializerMethod: companionSerializerSymbol,
            generatedSerializerClass: generatedSerializerClassSymbol,
            companionObjectSymbol: compID,
            serializableProperties: serializableProps
        )
    }

    private static func collectSerializableProperties(
        for classID: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [SerializationPropertyInfo] {
        symbols.declaredChildren(of: classID).compactMap { childID -> SerializationPropertyInfo? in
            guard let child = symbols.symbol(childID),
                  child.kind == .property,
                  !child.flags.contains(.synthetic),
                  !child.flags.contains(.static)
            else { return nil }
            let anns = symbols.annotations(for: childID)
            if anns.contains(where: { $0.annotationFQName == KnownCompilerAnnotation.serializationTransient.qualifiedName }) {
                return nil
            }
            var serialName = interner.resolve(child.name)
            if let snAnn = anns.first(where: { $0.annotationFQName == KnownCompilerAnnotation.serializationSerialName.qualifiedName }),
               let arg = snAnn.arguments.first
            {
                let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "value=", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
                    serialName = String(trimmed.dropFirst().dropLast())
                } else if !trimmed.isEmpty {
                    serialName = trimmed
                }
            }
            return SerializationPropertyInfo(symbol: childID, serialName: serialName)
        }
    }

    private static func synthesizeEnumSerializer(
        for classSymbol: SemanticSymbol,
        classType: TypeID,
        context: CompilerPluginSemaContext
    ) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let classID = classSymbol.id
        let serializerName = interner.intern("serializer")
        let serializerFQName = classSymbol.fqName + [serializerName]

        if let existing = symbols.lookupAll(fqName: serializerFQName).first(where: { candidate in
            guard let existingInfo = symbols.symbol(candidate),
                  existingInfo.kind == .function,
                  existingInfo.flags.contains(.static)
            else { return false }
            return symbols.parentSymbol(for: candidate) == classID
        }) {
            context.sema.serializationClasses[classID] = SerializationClassInfo(
                companionSerializerMethod: existing,
                companionObjectSymbol: nil,
                serializableProperties: []
            )
            return
        }

        if let companionID = symbols.companionObjectSymbol(for: classID),
           let companion = symbols.symbol(companionID),
           let companionSerializer = symbols.lookupAll(fqName: companion.fqName + [serializerName]).first(where: { candidate in
               symbols.symbol(candidate)?.kind == .function && symbols.parentSymbol(for: candidate) == companionID
           })
        {
            context.sema.serializationClasses[classID] = SerializationClassInfo(
                companionSerializerMethod: companionSerializer,
                companionObjectSymbol: companionID,
                serializableProperties: []
            )
            return
        }

        let serializerSym = symbols.define(
            kind: .function,
            name: serializerName,
            fqName: serializerFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(classID, for: serializerSym)
        let returnType = resolveKSerializerType(
            for: classType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false),
            for: serializerSym
        )
        context.sema.serializationClasses[classID] = SerializationClassInfo(
            companionSerializerMethod: serializerSym,
            companionObjectSymbol: nil,
            serializableProperties: []
        )
    }

    private static func resolveKSerializerSymbol(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let kSerializerFQName = [
            interner.intern("kotlinx"),
            interner.intern("serialization"),
            interner.intern("KSerializer"),
        ]
        if let sym = symbols.lookup(fqName: kSerializerFQName) { return sym }
        if let sym = symbols.lookup(fqName: [interner.intern("KSerializer")]) { return sym }
        return symbols.lookupByShortName(interner.intern("KSerializer")).first(where: {
            let k = symbols.symbol($0)?.kind
            return k == .interface || k == .class
        })
    }

    private static func resolveSerializationType(
        fqName: [String],
        shortName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let internedFQ = fqName.map { interner.intern($0) }
        if let sym = symbols.lookup(fqName: internedFQ)
            ?? symbols.lookup(fqName: [interner.intern(shortName)])
            ?? symbols.lookupByShortName(interner.intern(shortName)).first(where: {
                let k = symbols.symbol($0)?.kind
                return k == .interface || k == .class
            })
        {
            return types.make(.classType(ClassType(
                classSymbol: sym,
                args: [],
                nullability: .nonNull
            )))
        }
        return types.anyType
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
