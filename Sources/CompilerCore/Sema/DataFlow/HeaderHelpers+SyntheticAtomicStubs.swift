import Foundation

/// Synthetic stdlib stubs for kotlin.concurrent atomic and lock types.
/// Registers constructors, load/store/exchange/compareAndSet/compareAndExchange methods,
/// arithmetic methods (AtomicInt/AtomicLong), and the `value` property.
extension DataFlowSemaPhase {
    func registerSyntheticAtomicStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let concurrentPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let atomicsPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent", "atomics"],
            symbols: symbols,
            interner: interner
        )
        let atomicsPkgSymbol = symbols.lookup(fqName: atomicsPkg) ?? .invalid

        let intType = types.intType
        let longType = types.longType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyNullableType = types.make(.any(.nullable))
        let stringType = types.stringType
        let unitType = types.unitType

        // -- AtomicInt --
        let atomicIntSymbol = ensureClassSymbol(
            named: "AtomicInt",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicIntType = types.make(.classType(ClassType(
            classSymbol: atomicIntSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicIntType, for: atomicIntSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            externalLinkName: "kk_atomic_int_create",
            paramType: intType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            getterLinkName: "kk_atomic_int_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner
        )

        registerAtomicArithmeticMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner
        )
        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicLong --
        let atomicLongSymbol = ensureClassSymbol(
            named: "AtomicLong",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicLongType = types.make(.classType(ClassType(
            classSymbol: atomicLongSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicLongType, for: atomicLongSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            externalLinkName: "kk_atomic_long_create",
            paramType: longType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            getterLinkName: "kk_atomic_long_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner
        )

        registerAtomicArithmeticMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner
        )
        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicReference<T> --
        let atomicRefSymbol = ensureClassSymbol(
            named: "AtomicReference",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        // AtomicReference stores values as Any? at the ABI level.
        registerAtomicConstructor(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            externalLinkName: "kk_atomic_ref_create",
            paramType: anyNullableType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            getterLinkName: "kk_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_ref",
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            prefix: "kk_atomic_ref",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicBoolean --
        let atomicBoolSymbol = ensureClassSymbol(
            named: "AtomicBoolean",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicBoolType = types.make(.classType(ClassType(
            classSymbol: atomicBoolSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicBoolType, for: atomicBoolSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            externalLinkName: "kk_atomic_bool_create",
            paramType: boolType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            getterLinkName: "kk_atomic_bool_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_bool",
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            prefix: "kk_atomic_bool",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- Experimental atomic array API --
        registerAtomicAnnotationClass(
            named: "ExperimentalAtomicApi",
            packageFQName: atomicsPkg,
            packageSymbol: atomicsPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        let atomicIntArraySymbol = ensureClassSymbol(
            named: "AtomicIntArray",
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicIntArrayType = types.make(.classType(ClassType(
            classSymbol: atomicIntArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicIntArrayType, for: atomicIntArraySymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            externalLinkName: "kk_atomic_int_array_create",
            paramType: intType,
            symbols: symbols,
            interner: interner
        )

        if let intArraySymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("IntArray")]) {
            let intArrayType = types.make(.classType(ClassType(
                classSymbol: intArraySymbol,
                args: [],
                nullability: .nonNull
            )))
            registerAtomicConstructor(
                ownerSymbol: atomicIntArraySymbol,
                ownerType: atomicIntArrayType,
                externalLinkName: "kk_atomic_int_array_createFromArray",
                paramType: intArrayType,
                symbols: symbols,
                interner: interner,
                paramName: "array"
            )
        }

        registerAtomicProperty(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            propertyName: "size",
            propertyType: intType,
            getterLinkName: "kk_atomic_int_array_size",
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "toString",
            externalLinkName: "kk_atomic_int_array_toString",
            returnType: stringType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "get",
            externalLinkName: "kk_atomic_int_array_get",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "loadAt",
            externalLinkName: "kk_atomic_int_array_get",
            returnType: intType,
            parameters: [(name: "index", type: intType)],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "set",
            externalLinkName: "kk_atomic_int_array_set",
            returnType: unitType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "storeAt",
            externalLinkName: "kk_atomic_int_array_set",
            returnType: unitType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "exchange",
            externalLinkName: "kk_atomic_int_array_exchange",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "exchangeAt",
            externalLinkName: "kk_atomic_int_array_exchange",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "getAndSet",
            externalLinkName: "kk_atomic_int_array_exchange",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "compareAndSet",
            externalLinkName: "kk_atomic_int_array_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: intType),
                (name: "newValue", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "compareAndSetAt",
            externalLinkName: "kk_atomic_int_array_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: intType),
                (name: "newValue", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "compareAndExchange",
            externalLinkName: "kk_atomic_int_array_compareAndExchange",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: intType),
                (name: "newValue", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicIntArraySymbol,
            ownerType: atomicIntArrayType,
            name: "compareAndExchangeAt",
            externalLinkName: "kk_atomic_int_array_compareAndExchange",
            returnType: intType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: intType),
                (name: "newValue", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )

        for (name, linkName, parameters) in [
            ("getAndAdd", "kk_atomic_int_array_getAndAdd", [(name: "index", type: intType), (name: "delta", type: intType)]),
            ("getAndAddAt", "kk_atomic_int_array_getAndAdd", [(name: "index", type: intType), (name: "delta", type: intType)]),
            ("addAndGet", "kk_atomic_int_array_addAndGet", [(name: "index", type: intType), (name: "delta", type: intType)]),
            ("addAndFetchAt", "kk_atomic_int_array_addAndGet", [(name: "index", type: intType), (name: "delta", type: intType)]),
            ("getAndIncrement", "kk_atomic_int_array_getAndIncrement", [(name: "index", type: intType)]),
            ("fetchAndIncrementAt", "kk_atomic_int_array_getAndIncrement", [(name: "index", type: intType)]),
            ("incrementAndGet", "kk_atomic_int_array_incrementAndGet", [(name: "index", type: intType)]),
            ("incrementAndFetchAt", "kk_atomic_int_array_incrementAndGet", [(name: "index", type: intType)]),
            ("getAndDecrement", "kk_atomic_int_array_getAndDecrement", [(name: "index", type: intType)]),
            ("fetchAndDecrementAt", "kk_atomic_int_array_getAndDecrement", [(name: "index", type: intType)]),
            ("decrementAndGet", "kk_atomic_int_array_decrementAndGet", [(name: "index", type: intType)]),
            ("decrementAndFetchAt", "kk_atomic_int_array_decrementAndGet", [(name: "index", type: intType)]),
        ] as [(String, String, [(name: String, type: TypeID)])] {
            registerAtomicMember(
                ownerSymbol: atomicIntArraySymbol,
                ownerType: atomicIntArrayType,
                name: name,
                externalLinkName: linkName,
                returnType: intType,
                parameters: parameters,
                symbols: symbols,
                interner: interner
            )
        }

        let intTransformType = types.make(.functionType(FunctionType(
            params: [intType],
            returnType: intType,
            isSuspend: false,
            nullability: .nonNull
        )))
        for (name, linkName) in [
            ("getAndUpdate", "kk_atomic_int_array_getAndUpdate"),
            ("fetchAndUpdateAt", "kk_atomic_int_array_getAndUpdate"),
            ("updateAndGet", "kk_atomic_int_array_updateAndGet"),
            ("updateAndFetchAt", "kk_atomic_int_array_updateAndGet"),
        ] as [(String, String)] {
            registerAtomicMember(
                ownerSymbol: atomicIntArraySymbol,
                ownerType: atomicIntArrayType,
                name: name,
                externalLinkName: linkName,
                returnType: intType,
                parameters: [
                    (name: "index", type: intType),
                    (name: "transform", type: intTransformType),
                ],
                symbols: symbols,
                interner: interner
            )
        }

        let atomicLongArraySymbol = ensureClassSymbol(
            named: "AtomicLongArray",
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicLongArrayType = types.make(.classType(ClassType(
            classSymbol: atomicLongArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicLongArrayType, for: atomicLongArraySymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            externalLinkName: "kk_atomic_long_array_create",
            paramType: intType,
            symbols: symbols,
            interner: interner
        )

        if let longArraySymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("LongArray")]) {
            let longArrayType = types.make(.classType(ClassType(
                classSymbol: longArraySymbol,
                args: [],
                nullability: .nonNull
            )))
            registerAtomicConstructor(
                ownerSymbol: atomicLongArraySymbol,
                ownerType: atomicLongArrayType,
                externalLinkName: "kk_atomic_long_array_createFromArray",
                paramType: longArrayType,
                symbols: symbols,
                interner: interner,
                paramName: "array"
            )
        }

        registerAtomicProperty(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            propertyName: "size",
            propertyType: intType,
            getterLinkName: "kk_atomic_long_array_size",
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "toString",
            externalLinkName: "kk_atomic_long_array_toString",
            returnType: stringType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "get",
            externalLinkName: "kk_atomic_long_array_get",
            returnType: longType,
            parameters: [(name: "index", type: intType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "loadAt",
            externalLinkName: "kk_atomic_long_array_get",
            returnType: longType,
            parameters: [(name: "index", type: intType)],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "set",
            externalLinkName: "kk_atomic_long_array_set",
            returnType: unitType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: longType),
            ],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "storeAt",
            externalLinkName: "kk_atomic_long_array_set",
            returnType: unitType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "exchange",
            externalLinkName: "kk_atomic_long_array_exchange",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "exchangeAt",
            externalLinkName: "kk_atomic_long_array_exchange",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "getAndSet",
            externalLinkName: "kk_atomic_long_array_exchange",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "compareAndSet",
            externalLinkName: "kk_atomic_long_array_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: longType),
                (name: "newValue", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "compareAndSetAt",
            externalLinkName: "kk_atomic_long_array_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: longType),
                (name: "newValue", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "compareAndExchange",
            externalLinkName: "kk_atomic_long_array_compareAndExchange",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: longType),
                (name: "newValue", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: atomicLongArraySymbol,
            ownerType: atomicLongArrayType,
            name: "compareAndExchangeAt",
            externalLinkName: "kk_atomic_long_array_compareAndExchange",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: longType),
                (name: "newValue", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )

        for (name, linkName, parameters) in [
            ("getAndAdd", "kk_atomic_long_array_getAndAdd", [(name: "index", type: intType), (name: "delta", type: longType)]),
            ("getAndAddAt", "kk_atomic_long_array_getAndAdd", [(name: "index", type: intType), (name: "delta", type: longType)]),
            ("addAndGet", "kk_atomic_long_array_addAndGet", [(name: "index", type: intType), (name: "delta", type: longType)]),
            ("addAndFetchAt", "kk_atomic_long_array_addAndGet", [(name: "index", type: intType), (name: "delta", type: longType)]),
            ("getAndIncrement", "kk_atomic_long_array_getAndIncrement", [(name: "index", type: intType)]),
            ("fetchAndIncrementAt", "kk_atomic_long_array_getAndIncrement", [(name: "index", type: intType)]),
            ("incrementAndGet", "kk_atomic_long_array_incrementAndGet", [(name: "index", type: intType)]),
            ("incrementAndFetchAt", "kk_atomic_long_array_incrementAndGet", [(name: "index", type: intType)]),
            ("getAndDecrement", "kk_atomic_long_array_getAndDecrement", [(name: "index", type: intType)]),
            ("fetchAndDecrementAt", "kk_atomic_long_array_getAndDecrement", [(name: "index", type: intType)]),
            ("decrementAndGet", "kk_atomic_long_array_decrementAndGet", [(name: "index", type: intType)]),
            ("decrementAndFetchAt", "kk_atomic_long_array_decrementAndGet", [(name: "index", type: intType)]),
        ] as [(String, String, [(name: String, type: TypeID)])] {
            registerAtomicMember(
                ownerSymbol: atomicLongArraySymbol,
                ownerType: atomicLongArrayType,
                name: name,
                externalLinkName: linkName,
                returnType: longType,
                parameters: parameters,
                symbols: symbols,
                interner: interner
            )
        }

        let longTransformType = types.make(.functionType(FunctionType(
            params: [longType],
            returnType: longType,
            isSuspend: false,
            nullability: .nonNull
        )))
        for (name, linkName) in [
            ("getAndUpdate", "kk_atomic_long_array_getAndUpdate"),
            ("fetchAndUpdateAt", "kk_atomic_long_array_getAndUpdate"),
            ("updateAndGet", "kk_atomic_long_array_updateAndGet"),
            ("updateAndFetchAt", "kk_atomic_long_array_updateAndGet"),
        ] as [(String, String)] {
            registerAtomicMember(
                ownerSymbol: atomicLongArraySymbol,
                ownerType: atomicLongArrayType,
                name: name,
                externalLinkName: linkName,
                returnType: longType,
                parameters: [
                    (name: "index", type: intType),
                    (name: "transform", type: longTransformType),
                ],
                symbols: symbols,
                interner: interner
            )
        }

        // -- Lock --
        let lockSymbol = ensureClassSymbol(
            named: "Lock",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let lockType = types.make(.classType(ClassType(
            classSymbol: lockSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(lockType, for: lockSymbol)
        registerAtomicMember(
            ownerSymbol: lockSymbol,
            ownerType: lockType,
            name: "withLock",
            externalLinkName: "kk_lock_withLock",
            returnType: types.anyType,
            parameters: [(
                name: "action",
                type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            )],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Helpers

    private func registerAtomicConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        paramType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        paramName: String = "initial"
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatch = symbols.lookupAll(fqName: ctorFQName).contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .constructor,
                  let sig = symbols.functionSignature(for: id)
            else { return false }
            return sig.parameterTypes == [paramType]
        }
        guard !hasMatch else { return }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        let internedParamName = interner.intern(paramName)
        let paramSymbol = symbols.define(
            kind: .valueParameter,
            name: internedParamName,
            fqName: ctorFQName + [internedParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ctorSymbol, for: paramSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [paramType],
                returnType: ownerType,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: ctorSymbol
        )
    }

    private func registerAtomicValueProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern("value")
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
        }) {
            symbols.setExternalLinkName(getterLinkName, for: existing)
            symbols.setPropertyType(valueType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(getterLinkName, for: propertySymbol)
        symbols.setPropertyType(valueType, for: propertySymbol)
    }

    private func registerAtomicProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        propertyName: String,
        propertyType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let internedPropertyName = interner.intern(propertyName)
        let propertyFQName = ownerInfo.fqName + [internedPropertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
        }) {
            symbols.setExternalLinkName(getterLinkName, for: existing)
            symbols.setPropertyType(propertyType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: internedPropertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(getterLinkName, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    private func registerAtomicCoreMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // load() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "load", externalLinkName: "\(prefix)_load",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // store(value: T) -> Unit (returns via side effect)
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "store", externalLinkName: "\(prefix)_store",
            returnType: unitType, parameters: [(name: "value", type: valueType)],
            symbols: symbols, interner: interner
        )
        // exchange(new: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "exchange", externalLinkName: "\(prefix)_exchange",
            returnType: valueType, parameters: [(name: "new", type: valueType)],
            symbols: symbols, interner: interner
        )
        // compareAndSet(expect: T, update: T) -> Boolean
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "compareAndSet", externalLinkName: "\(prefix)_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            symbols: symbols, interner: interner
        )
        // compareAndExchange(expect: T, update: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "compareAndExchange", externalLinkName: "\(prefix)_compareAndExchange",
            returnType: valueType,
            parameters: [
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicArithmeticMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // fetchAndAdd(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndAdd", externalLinkName: "\(prefix)_fetchAndAdd",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            symbols: symbols, interner: interner
        )
        // addAndFetch(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "addAndFetch", externalLinkName: "\(prefix)_addAndFetch",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            symbols: symbols, interner: interner
        )
        // fetchAndIncrement() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndIncrement", externalLinkName: "\(prefix)_fetchAndIncrement",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // incrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "incrementAndFetch", externalLinkName: "\(prefix)_incrementAndFetch",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // decrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "decrementAndFetch", externalLinkName: "\(prefix)_decrementAndFetch",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicGetAndUpdateMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let transformType = types.make(.functionType(FunctionType(
            params: [valueType],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))
        // getAndUpdate(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "getAndUpdate", externalLinkName: "\(prefix)_getAndUpdate",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
            symbols: symbols, interner: interner
        )
        // updateAndGet(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "updateAndGet", externalLinkName: "\(prefix)_updateAndGet",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { id in
            guard let sig = symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == parameters.map(\.type) &&
                sig.returnType == returnType
        }) == nil else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func ensureAtomicPackage(
        path: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for component in path {
            let interned = interner.intern(component)
            fqName.append(interned)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: interned,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }

    private func registerAtomicAnnotationClass(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        if let existing = symbols.lookup(fqName: classFQName) {
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
            return
        }

        let classSymbol = symbols.define(
            kind: .annotationClass,
            name: className,
            fqName: classFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
    }

}
