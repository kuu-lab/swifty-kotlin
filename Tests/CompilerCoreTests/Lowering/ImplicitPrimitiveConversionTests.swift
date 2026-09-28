#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ImplicitPrimitiveConversionTests {
    @Test
    func testImplicitSmallIntegerConversionsBindAndLowerToRealBridgesOrCopies() throws {
        let source = """
        fun Byte.byteInt(): Int = toInt()
        fun Byte.byteShort(): Short = toShort()
        fun Byte.byteUnsigned(): UInt = toUInt()
        fun Byte.byteFloat(): Float = toFloat()
        fun Byte.byteChar(): Char = toChar()
        fun Short.shortInt(): Int = toInt()
        fun Short.shortByte(): Byte = toByte()
        fun Short.shortDouble(): Double = toDouble()
        fun Short.shortUByte(): UByte = toUByte()
        fun Short.shortChar(): Char = toChar()
        """
        let expectedLinks: [(function: String, link: String?)] = [
            ("byteInt", nil),
            ("byteShort", nil),
            ("byteUnsigned", "kk_int_to_uint"),
            ("byteFloat", "kk_int_to_float"),
            ("byteChar", "kk_byte_to_char"),
            ("shortInt", nil),
            ("shortByte", "kk_int_to_byte"),
            ("shortDouble", "kk_int_to_double_bits"),
            ("shortUByte", "kk_int_to_ubyte"),
            ("shortChar", "kk_short_to_char"),
        ]

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)

            for entry in expectedLinks {
                let body = try findKIRFunctionBody(named: entry.function, in: module, interner: ctx.interner)
                let links = body.compactMap { instruction -> String? in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                    return ctx.interner.resolve(callee)
                }
                #expect(!links.contains("kk_primitive_identity"), "\(entry.function) must never call a missing ABI symbol")
                if let expected = entry.link {
                    #expect(links.contains(expected), "\(entry.function) must use \(expected); got \(links)")
                } else {
                    #expect(body.contains { if case .copy = $0 { return true }; return false }, "\(entry.function) must copy its receiver")
                }
            }
        }
    }

    @Test
    func testImplicitPrimitiveIdentitiesNeverEmitRuntimeCalls() throws {
        let source = """
        fun Byte.idByte(): Byte = toByte()
        fun Short.idShort(): Short = toShort()
        fun Int.idInt(): Int = toInt()
        fun Long.idLong(): Long = toLong()
        fun Float.idFloat(): Float = toFloat()
        fun Double.idDouble(): Double = toDouble()
        fun Char.idChar(): Char = toChar()
        fun UByte.idUByte(): UByte = toUByte()
        fun UShort.idUShort(): UShort = toUShort()
        fun UInt.idUInt(): UInt = toUInt()
        fun ULong.idULong(): ULong = toULong()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            for name in [
                "idByte", "idShort", "idInt", "idLong", "idFloat", "idDouble",
                "idChar", "idUByte", "idUShort", "idUInt", "idULong",
            ] {
                let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
                let calls = body.compactMap { instruction -> String? in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                    return ctx.interner.resolve(callee)
                }
                #expect(calls.isEmpty, "\(name) must be an identity copy; calls: \(calls)")
                #expect(body.contains { if case .copy = $0 { return true }; return false }, "\(name) must copy its receiver")
            }
        }
    }

    @Test
    func testImplicitConversionRejectsInvalidReceiverAndArguments() throws {
        let source = """
        fun Boolean.invalid(): Int = toInt()
        fun Byte.invalidArity(): UInt = toUInt(1)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count >= 2, "both calls must remain invalid: \(errors)")
        }
    }
}
#endif
