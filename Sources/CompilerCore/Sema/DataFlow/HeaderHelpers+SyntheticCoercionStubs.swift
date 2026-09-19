
// Coercion extension stubs (STDLIB-150) for kotlin.ranges.
// Int/Long/Double/Float coercion tests: CoercionSyntheticStubTests (TEST-002)
//
// KSP-1544 (KUU-588): the remaining registrations are all bucket (c)
// compiler/runtime residuals — language-core primitive casts lowered directly
// to kk_* runtime symbols (see docs/stdlib-pipeline.md §9). The source-backed
// (b) surface is fully migrated: range coercion lives in
// Stdlib/kotlin/ranges/RangeCoercion.kt, and Float/Double.toByte()/toShort()
// live in Stdlib/kotlin/Numbers.kt.

extension DataFlowSemaPhase {
    func registerSyntheticCoercionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        // Unsigned coercion overloads are provided by bundled Kotlin source (RangeCoercion.kt).

        // STDLIB-NUM-130: isNaN / isInfinite / isFinite

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions.
        // KSP-646: Double/Float isNaN, isInfinite, and isFinite now use IEEE
        // 754 bit-pattern checks in bundled Kotlin (Stdlib/kotlin/util/Numbers.kt).
        // KSP-647: toBits and toRawBits are bundled Kotlin extensions in the
        // same source file, backed by __kk_* declarations there.

        // Primitive bit-count and one-bit functions are declared in bundled Kotlin source
        // (Stdlib/kotlin/BitOperations.kt) since KSP-643/KSP-644.
        // Use if-let instead of guard-return so future registrations below are not skipped.
        if let kotlinPackageSymbol = symbols.lookup(fqName: kotlinPkg) {
            // MARK: - Primitive Type Conversion Functions (STDLIB-PRIM-002)

            // Int conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_int_to_byte",
                receiverType: types.intType,
                parameters: [],
                returnType: types.byteType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_int_to_short",
                receiverType: types.intType,
                parameters: [],
                returnType: types.shortType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_int_to_int",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toLong",
                externalLinkName: "kk_int_to_long",
                receiverType: types.intType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toFloat",
                externalLinkName: "kk_int_to_float",
                receiverType: types.intType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            // KSP-1536: Int.toDouble() and Int.toChar() are declared in bundled
            // Kotlin source (`Stdlib/kotlin/Numbers.kt`).

            registerSyntheticCoercionFunction(
                named: "toUByte",
                externalLinkName: "kk_int_to_ubyte",
                receiverType: types.intType,
                parameters: [],
                returnType: types.ubyteType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toUShort",
                externalLinkName: "kk_int_to_ushort",
                receiverType: types.intType,
                parameters: [],
                returnType: types.ushortType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_int_to_uint",
                receiverType: types.intType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_int_to_ulong",
                receiverType: types.intType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            // Long conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_long_to_byte",
                receiverType: types.longType,
                parameters: [],
                returnType: types.byteType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_long_to_short",
                receiverType: types.longType,
                parameters: [],
                returnType: types.shortType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_long_to_int",
                receiverType: types.longType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toFloat",
                externalLinkName: "kk_long_to_float",
                receiverType: types.longType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toDouble",
                externalLinkName: "kk_long_to_double",
                receiverType: types.longType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toUByte",
                externalLinkName: "kk_long_to_ubyte",
                receiverType: types.longType,
                parameters: [],
                returnType: types.ubyteType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toUShort",
                externalLinkName: "kk_long_to_ushort",
                receiverType: types.longType,
                parameters: [],
                returnType: types.ushortType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_long_to_uint",
                receiverType: types.longType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_long_to_ulong",
                receiverType: types.longType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

            // KSP-1544: Float.toByte()/toShort() and Double.toByte()/toShort()
            // are source-backed in Stdlib/kotlin/Numbers.kt (toInt().toX()
            // composition with error-level deprecation metadata).

            // Double conversion functions
            registerSyntheticCoercionFunction(
                named: "toFloat",
                externalLinkName: "kk_double_to_float",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner,
                types: types
            )

        }

    }

    private func registerSyntheticCoercionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]

        // Check if already registered with same signature
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for param in parameters {
            let paramName = interner.intern(param.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: functionSymbol
        )
    }
}
