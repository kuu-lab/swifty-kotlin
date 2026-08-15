
// Coercion extension stubs (STDLIB-150) for kotlin.ranges.
// Int/Long/Double/Float coercion tests: CoercionSyntheticStubTests (TEST-002)

extension DataFlowSemaPhase {
    func registerSyntheticCoercionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        // Unsigned coercion overloads are provided by bundled Kotlin source (RangeCoercion.kt).

        let kotlinMathPkg = kotlinPkg + [interner.intern("math")]
        if symbols.lookup(fqName: kotlinMathPkg) == nil {
            let mathName = interner.intern("math")
            let mathSym = symbols.define(kind: .package, name: mathName, fqName: kotlinMathPkg, declSite: nil, visibility: .public, flags: [.synthetic])
            if let kotlinSym = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(kotlinSym, for: mathSym)
            }
        }
        if let mathPackageSymbol = symbols.lookup(fqName: kotlinMathPkg) {
            registerSyntheticCoercionFunction(
                named: "pow",
                externalLinkName: "kk_math_pow",
                receiverType: types.doubleType,
                parameters: [(name: "x", type: types.doubleType)],
                returnType: types.doubleType,
                packageFQName: kotlinMathPkg,
                packageSymbol: mathPackageSymbol,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-NUM-130: isNaN / isInfinite / isFinite

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions.
        // KSP-646: Double/Float isNaN, isInfinite, and isFinite now use IEEE
        // 754 bit-pattern checks in bundled Kotlin (Stdlib/kotlin/util/Numbers.kt).
        // KSP-647: toBits and toRawBits are bundled Kotlin extensions in the
        // same source file, backed by __kk_* declarations there.

        // STDLIB-BIT-007: Additional bit manipulation functions.
        // countOneBits / countLeadingZeroBits / countTrailingZeroBits are declared in
        // bundled Kotlin source (Stdlib/kotlin/BitOperations.kt) since KSP-643.
        // Use if-let instead of guard-return so future registrations below are not skipped.
        if let kotlinPackageSymbol = symbols.lookup(fqName: kotlinPkg) {
            // Zero-argument Int functions
            registerSyntheticCoercionFunction(
                named: "highestOneBit",
                externalLinkName: "kk_int_highestOneBit",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "lowestOneBit",
                externalLinkName: "kk_int_lowestOneBit",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "takeHighestOneBit",
                externalLinkName: "kk_int_takeHighestOneBit",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "takeLowestOneBit",
                externalLinkName: "kk_int_takeLowestOneBit",
                receiverType: types.intType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // KSP-642: Int rotateLeft / rotateRight are declared in bundled Kotlin
            // source (`Stdlib/kotlin/Numbers.kt`).

            // Zero-argument Long functions
            registerSyntheticCoercionFunction(
                named: "highestOneBit",
                externalLinkName: "kk_long_highestOneBit",
                receiverType: types.longType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "lowestOneBit",
                externalLinkName: "kk_long_lowestOneBit",
                receiverType: types.longType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "takeHighestOneBit",
                externalLinkName: "kk_long_takeHighestOneBit",
                receiverType: types.longType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "takeLowestOneBit",
                externalLinkName: "kk_long_takeLowestOneBit",
                receiverType: types.longType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // KSP-642: Long rotateLeft / rotateRight are declared in bundled Kotlin
            // source (`Stdlib/kotlin/Numbers.kt`).

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
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toDouble",
                externalLinkName: "kk_int_to_double_bits",
                receiverType: types.intType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toChar",
                externalLinkName: "kk_int_to_char",
                receiverType: types.intType,
                parameters: [],
                returnType: types.charType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUByte",
                externalLinkName: "kk_int_to_ubyte",
                receiverType: types.intType,
                parameters: [],
                returnType: types.ubyteType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toChar",
                externalLinkName: "kk_long_to_char",
                receiverType: types.longType,
                parameters: [],
                returnType: types.charType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
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
                interner: interner
            )

            // Float conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_float_to_int",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_float_to_int",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_float_to_int",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toLong",
                externalLinkName: "kk_float_to_long",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toDouble",
                externalLinkName: "kk_float_to_double_bits",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.doubleType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toChar",
                externalLinkName: "kk_float_to_char",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.charType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_float_to_uint",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_float_to_ulong",
                receiverType: types.floatType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Double conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_double_to_int",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_double_to_int",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_double_to_int",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toLong",
                externalLinkName: "kk_double_to_long",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toFloat",
                externalLinkName: "kk_double_to_float",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.floatType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toChar",
                externalLinkName: "kk_double_to_char",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.charType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_double_to_uint",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_double_to_ulong",
                receiverType: types.doubleType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            // Char conversion functions
            registerSyntheticCoercionFunction(
                named: "toByte",
                externalLinkName: "kk_char_to_int",
                receiverType: types.charType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toShort",
                externalLinkName: "kk_char_to_int",
                receiverType: types.charType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toInt",
                externalLinkName: "kk_char_to_int",
                receiverType: types.charType,
                parameters: [],
                returnType: types.intType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toLong",
                externalLinkName: "kk_char_to_long",
                receiverType: types.charType,
                parameters: [],
                returnType: types.longType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toUInt",
                externalLinkName: "kk_char_to_uint",
                receiverType: types.charType,
                parameters: [],
                returnType: types.uintType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )

            registerSyntheticCoercionFunction(
                named: "toULong",
                externalLinkName: "kk_char_to_ulong",
                receiverType: types.charType,
                parameters: [],
                returnType: types.ulongType,
                packageFQName: kotlinPkg,
                packageSymbol: kotlinPackageSymbol,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-NUM-130: Double.fromBits(bits: Long) and Float.fromBits(bits: Int)
        // remain top-level synthetic registrations because primitive Double and
        // Float do not expose a Companion type in the compiler's core model.
        registerSyntheticTopLevelFunction(
            named: "fromBits",
            packageFQName: kotlinPkg,
            parameters: [(name: "bits", type: types.longType)],
            returnType: types.doubleType,
            externalLinkName: "__kk_double_fromBits",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "fromBits",
            packageFQName: kotlinPkg,
            parameters: [(name: "bits", type: types.intType)],
            returnType: types.floatType,
            externalLinkName: "__kk_float_fromBits",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        // Avoid duplicate registration (same signature).
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == nil
                && sig.parameterTypes == parameters.map(\.type)
                && sig.returnType == returnType
        }) {
            return
        }
        if hasImportedLibrarySymbol(fqName: functionFQName, kind: .function, symbols: symbols) {
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
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
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let deprecatedAnnotations = syntheticDeprecatedAnnotationsForCoercion(name: name)

        // Check if already registered with same signature
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) {
            if !deprecatedAnnotations.isEmpty {
                symbols.setAnnotations(deprecatedAnnotations, for: existing)
            }
            return
        }
        if hasImportedLibrarySymbol(fqName: functionFQName, kind: .function, symbols: symbols) {
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
        if !deprecatedAnnotations.isEmpty {
            symbols.setAnnotations(deprecatedAnnotations, for: functionSymbol)
        }

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

    private func syntheticDeprecatedAnnotationsForCoercion(
        name: String
    ) -> [MetadataAnnotationRecord] {
        guard name == "toChar" else {
            return []
        }
        let deprecatedMessage = "Use toInt().toChar() or Char(code) instead."
        let deprecatedArguments = [
            "message = \"\(deprecatedMessage)\"",
            "replaceWith = ReplaceWith(\"toInt().toChar()\")",
        ]
        return [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: deprecatedArguments
            ),
        ]
    }
}
