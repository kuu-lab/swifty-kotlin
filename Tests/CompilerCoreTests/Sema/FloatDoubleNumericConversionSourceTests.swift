#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1538: floating-point numeric conversion members are bundled Kotlin
/// declarations, with hidden runtime bridges limited to raw ABI transport.
@Suite
struct FloatDoubleNumericConversionSourceTests {
    @Test
    func floatingPointConversionsResolveToBundledKotlin() throws {
        let ctx = makeContextFromSource("""
        @file:Suppress("DEPRECATION_ERROR")
        fun doubleToInt(value: Double): Int = value.toInt()
        fun doubleToLong(value: Double): Long = value.toLong()
        fun doubleToChar(value: Double): Char = value.toChar()
        fun floatToInt(value: Float): Int = value.toInt()
        fun floatToLong(value: Float): Long = value.toLong()
        fun floatToDouble(value: Float): Double = value.toDouble()
        fun floatToChar(value: Float): Char = value.toChar()
        fun doubleToByte(value: Double): Byte = value.toByte()
        fun doubleToShort(value: Double): Short = value.toShort()
        fun floatToByte(value: Float): Byte = value.toByte()
        fun floatToShort(value: Float): Short = value.toShort()
        """)

        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected floating-point conversions to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let expectedConversions: [(name: String, receiver: TypeID, result: TypeID)] = [
            ("toInt", sema.types.doubleType, sema.types.intType),
            ("toLong", sema.types.doubleType, sema.types.longType),
            ("toChar", sema.types.doubleType, sema.types.charType),
            ("toInt", sema.types.floatType, sema.types.intType),
            ("toLong", sema.types.floatType, sema.types.longType),
            ("toDouble", sema.types.floatType, sema.types.doubleType),
            ("toChar", sema.types.floatType, sema.types.charType),
            ("toByte", sema.types.doubleType, sema.types.byteType),
            ("toShort", sema.types.doubleType, sema.types.shortType),
            ("toByte", sema.types.floatType, sema.types.byteType),
            ("toShort", sema.types.floatType, sema.types.shortType),
        ]

        for conversion in expectedConversions {
            let candidates = sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern(conversion.name),
            ])
            let sourceSymbol = candidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiver = signature.receiverType,
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return receiver == conversion.receiver
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == conversion.result
                    && ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/Numbers.kt"
            }
            #expect(sourceSymbol != nil, "Expected kotlin.\(conversion.name) in Numbers.kt")
            if let sourceSymbol {
                #expect(sema.symbols.isSourceBackedSymbol(sourceSymbol))
                #expect(sema.symbols.externalLinkName(for: sourceSymbol) == nil)
            }
        }
    }

    // KSP-1544 (KUU-588): Float/Double.toByte()/toShort() are deprecated at
    // error level since Kotlin 1.5. Unsuppressed calls must fail Sema like
    // real kotlinc 2.3.10, and no synthetic stub may remain under kotlin.toByte /
    // kotlin.toShort for floating-point receivers.
    @Test
    func floatingPointByteShortConversionsAreErrorLevelDeprecated() throws {
        let ctx = makeContextFromSource("""
        fun doubleToByte(value: Double): Byte = value.toByte()
        fun doubleToShort(value: Double): Short = value.toShort()
        fun floatToByte(value: Float): Byte = value.toByte()
        fun floatToShort(value: Float): Short = value.toShort()
        """)

        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Expected floating-point Byte/Short conversions to be rejected as error-level deprecated"
        )

        let sema = try #require(ctx.sema)
        let fpReceivers = [sema.types.doubleType, sema.types.floatType]
        for name in ["toByte", "toShort"] {
            let candidates = sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern(name),
            ])
            let staleStub = candidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiver = signature.receiverType
                else {
                    return false
                }
                return fpReceivers.contains(receiver)
                    && signature.parameterTypes.isEmpty
                    && !sema.symbols.isSourceBackedSymbol(symbolID)
            }
            #expect(staleStub == nil, "Expected no synthetic kotlin.\(name) stub for Float/Double")
        }
    }
}
#endif
