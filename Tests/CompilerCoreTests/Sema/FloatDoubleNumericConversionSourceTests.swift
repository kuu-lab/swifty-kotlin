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
        fun doubleToInt(value: Double): Int = value.toInt()
        fun doubleToLong(value: Double): Long = value.toLong()
        fun doubleToChar(value: Double): Char = value.toChar()
        fun floatToInt(value: Float): Int = value.toInt()
        fun floatToLong(value: Float): Long = value.toLong()
        fun floatToDouble(value: Float): Double = value.toDouble()
        fun floatToChar(value: Float): Char = value.toChar()
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
}
#endif
