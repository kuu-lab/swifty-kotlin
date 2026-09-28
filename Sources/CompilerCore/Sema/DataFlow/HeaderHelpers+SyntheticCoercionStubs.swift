
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

            // Unsigned integer conversion functions (KUU-919). Bundled Kotlin
            // source declares no UByte/UShort/UInt/ULong `toX` members, so an
            // implicit-receiver call such as `toShort()` inside
            // `fun UShort.f()` had no receiver-matching `kotlin.toX` overload
            // and failed overload resolution. Explicit receivers are already
            // handled by the primitive-member fast path; these stubs expose
            // the same surface to implicit-receiver calls. Same-type identity
            // conversions (UByte.toUByte() etc.) have no runtime callee and
            // are intentionally omitted.
            let unsignedConversionStubs: [(
                name: String,
                link: String,
                receiver: TypeID,
                result: TypeID
            )] = [
                ("toByte", "kk_ubyte_to_byte", types.ubyteType, types.byteType),
                ("toShort", "kk_ubyte_to_short", types.ubyteType, types.shortType),
                ("toInt", "kk_ubyte_to_int", types.ubyteType, types.intType),
                ("toLong", "kk_ubyte_to_long", types.ubyteType, types.longType),
                ("toFloat", "kk_ubyte_to_float", types.ubyteType, types.floatType),
                ("toDouble", "kk_ubyte_to_double", types.ubyteType, types.doubleType),
                ("toUInt", "kk_ubyte_to_uint", types.ubyteType, types.uintType),
                ("toULong", "kk_ubyte_to_ulong", types.ubyteType, types.ulongType),
                ("toUShort", "kk_ubyte_to_ushort", types.ubyteType, types.ushortType),
                ("toByte", "kk_ushort_to_byte", types.ushortType, types.byteType),
                ("toShort", "kk_ushort_to_short", types.ushortType, types.shortType),
                ("toInt", "kk_ushort_to_int", types.ushortType, types.intType),
                ("toLong", "kk_ushort_to_long", types.ushortType, types.longType),
                ("toFloat", "kk_ushort_to_float", types.ushortType, types.floatType),
                ("toDouble", "kk_ushort_to_double", types.ushortType, types.doubleType),
                ("toUByte", "kk_ushort_to_ubyte", types.ushortType, types.ubyteType),
                ("toUInt", "kk_ushort_to_uint", types.ushortType, types.uintType),
                ("toULong", "kk_ushort_to_ulong", types.ushortType, types.ulongType),
                ("toByte", "kk_uint_to_byte", types.uintType, types.byteType),
                ("toShort", "kk_uint_to_short", types.uintType, types.shortType),
                ("toInt", "kk_uint_to_int", types.uintType, types.intType),
                ("toLong", "kk_uint_to_long", types.uintType, types.longType),
                ("toFloat", "kk_uint_to_float", types.uintType, types.floatType),
                ("toDouble", "kk_uint_to_double", types.uintType, types.doubleType),
                ("toUByte", "kk_uint_to_ubyte", types.uintType, types.ubyteType),
                ("toUShort", "kk_uint_to_ushort", types.uintType, types.ushortType),
                ("toULong", "kk_uint_to_ulong", types.uintType, types.ulongType),
                ("toByte", "kk_ulong_to_byte", types.ulongType, types.byteType),
                ("toShort", "kk_ulong_to_short", types.ulongType, types.shortType),
                ("toInt", "kk_ulong_to_int", types.ulongType, types.intType),
                ("toLong", "kk_ulong_to_long", types.ulongType, types.longType),
                ("toFloat", "kk_ulong_to_float", types.ulongType, types.floatType),
                ("toDouble", "kk_ulong_to_double", types.ulongType, types.doubleType),
                ("toUByte", "kk_ulong_to_ubyte", types.ulongType, types.ubyteType),
                ("toUShort", "kk_ulong_to_ushort", types.ulongType, types.ushortType),
                // KSP-1533: there is no kk_ulong_to_uint; kk_long_to_uint
                // truncates the same raw-register representation.
                ("toUInt", "kk_long_to_uint", types.ulongType, types.uintType),
            ]
            for stub in unsignedConversionStubs {
                registerSyntheticCoercionFunction(
                    named: stub.name,
                    externalLinkName: stub.link,
                    receiverType: stub.receiver,
                    parameters: [],
                    returnType: stub.result,
                    packageFQName: kotlinPkg,
                    packageSymbol: kotlinPackageSymbol,
                    symbols: symbols,
                    interner: interner,
                    types: types
                )
            }

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
