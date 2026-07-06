/// Synthetic `AbstractIterator` and primitive iterator stubs
/// (STDLIB-COL-TYPE-002).
///
/// Kept separate from `HeaderHelpers+SyntheticIterableRegistry.swift` because
/// iterator shells remain residual compiler surface.
extension DataFlowSemaPhase {
    /// Register `kotlin.collections.AbstractIterator<T>` surface (STDLIB-COL-TYPE-002).
    func registerSyntheticAbstractIteratorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iteratorSymbol: SymbolID
    ) {
        let abstractIteratorName = interner.intern("AbstractIterator")
        let abstractIteratorFQName = kotlinCollectionsPkg + [abstractIteratorName]
        let abstractIteratorSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractIteratorFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractIteratorName,
                fqName: abstractIteratorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = abstractIteratorFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractIteratorSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: abstractIteratorSymbol)

        let abstractIteratorType = types.make(.classType(ClassType(
            classSymbol: abstractIteratorSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractIteratorType, for: abstractIteratorSymbol)
        symbols.setDirectSupertypes([iteratorSymbol], for: abstractIteratorSymbol)
        types.setNominalDirectSupertypes([iteratorSymbol], for: abstractIteratorSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractIteratorSymbol, supertype: iteratorSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractIteratorSymbol, supertype: iteratorSymbol)

        let initName = interner.intern("<init>")
        let initFQName = abstractIteratorFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractIteratorSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractIteratorType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        let abstractIteratorContext = SyntheticStubRegistrationContext(
            ownerFQName: abstractIteratorFQName,
            parentSymbol: abstractIteratorSymbol,
            typeParameterSymbolsByName: ["T": typeParamSymbol]
        )
        registerSyntheticFunctionStubs(
            [
                SyntheticFunctionStubSpec(
                    name: "computeNext",
                    receiverType: .typeID(abstractIteratorType),
                    returnType: .unit,
                    visibility: .protected,
                    flags: [.synthetic, .abstractType],
                    typeParameterNames: ["T"],
                    classTypeParameterCount: 1
                ),
                SyntheticFunctionStubSpec(
                    name: "done",
                    receiverType: .typeID(abstractIteratorType),
                    returnType: .unit,
                    visibility: .protected,
                    flags: [.synthetic],
                    typeParameterNames: ["T"],
                    classTypeParameterCount: 1
                ),
                SyntheticFunctionStubSpec(
                    name: "setNext",
                    receiverType: .typeID(abstractIteratorType),
                    parameters: [
                        SyntheticStubParameterSpec(name: "value", type: .typeID(typeParamType)),
                    ],
                    returnType: .unit,
                    visibility: .protected,
                    flags: [.synthetic],
                    typeParameterNames: ["T"],
                    classTypeParameterCount: 1
                ),
                SyntheticFunctionStubSpec(
                    name: "hasNext",
                    receiverType: .typeID(abstractIteratorType),
                    returnType: .boolean,
                    flags: [.synthetic, .openType, .overrideMember, .operatorFunction],
                    typeParameterNames: ["T"],
                    classTypeParameterCount: 1
                ),
                SyntheticFunctionStubSpec(
                    name: "next",
                    receiverType: .typeID(abstractIteratorType),
                    returnType: .typeID(typeParamType),
                    flags: [.synthetic, .openType, .overrideMember, .operatorFunction],
                    typeParameterNames: ["T"],
                    classTypeParameterCount: 1
                ),
            ],
            context: abstractIteratorContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    /// Register primitive iterator class surfaces (STDLIB-COL-TYPE-004).
    func registerSyntheticPrimitiveIteratorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iteratorSymbol: SymbolID
    ) {
        let specs: [(className: String, nextName: String, elementType: TypeID)] = [
            ("BooleanIterator", "nextBoolean", types.booleanType),
            ("ByteIterator", "nextByte", types.intType),
            ("ShortIterator", "nextShort", types.intType),
            ("IntIterator", "nextInt", types.intType),
            ("LongIterator", "nextLong", types.longType),
            ("FloatIterator", "nextFloat", types.floatType),
            ("DoubleIterator", "nextDouble", types.doubleType),
            ("CharIterator", "nextChar", types.charType),
        ]

        for spec in specs {
            registerSyntheticPrimitiveIteratorStub(
                named: spec.className,
                nextMemberName: spec.nextName,
                elementType: spec.elementType,
                symbols: symbols,
                types: types,
                interner: interner,
                kotlinCollectionsPkg: kotlinCollectionsPkg,
                iteratorSymbol: iteratorSymbol
            )
        }
    }

    func registerSyntheticPrimitiveIteratorStub(
        named className: String,
        nextMemberName: String,
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iteratorSymbol: SymbolID
    ) {
        let classInternedName = interner.intern(className)
        let classFQName = kotlinCollectionsPkg + [classInternedName]
        let classSymbol: SymbolID = if let existing = symbols.lookup(fqName: classFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: classInternedName,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)
        symbols.setDirectSupertypes([iteratorSymbol], for: classSymbol)
        types.setNominalDirectSupertypes([iteratorSymbol], for: classSymbol)
        symbols.setSupertypeTypeArgs([.out(elementType)], for: classSymbol, supertype: iteratorSymbol)
        types.setNominalSupertypeTypeArgs([.out(elementType)], for: classSymbol, supertype: iteratorSymbol)

        let initName = interner.intern("<init>")
        let initFQName = classFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: classType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [],
                    classTypeParameterCount: 0
                ),
                for: initSymbol
            )
        }

        let primitiveIteratorContext = SyntheticStubRegistrationContext(
            ownerFQName: classFQName,
            parentSymbol: classSymbol
        )
        registerSyntheticFunctionStubs(
            [
                SyntheticFunctionStubSpec(
                    name: nextMemberName,
                    receiverType: .typeID(classType),
                    returnType: .typeID(elementType),
                    flags: [.synthetic, .abstractType]
                ),
                SyntheticFunctionStubSpec(
                    name: "next",
                    receiverType: .typeID(classType),
                    returnType: .typeID(elementType),
                    flags: [.synthetic, .openType, .overrideMember, .operatorFunction]
                ),
            ],
            context: primitiveIteratorContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

}
