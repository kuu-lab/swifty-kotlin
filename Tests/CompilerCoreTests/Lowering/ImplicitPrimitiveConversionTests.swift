#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ImplicitPrimitiveConversionTests {
    @Test
    func testSmallSignedIntegerToUShortCallsUseExistingRuntimeBridge() throws {
        let source = """
        fun byteExplicit(value: Byte): UShort = value.toUShort()
        fun shortExplicit(value: Short): UShort = value.toUShort()
        fun byteSafe(value: Byte?): UShort? = value?.toUShort()
        fun shortSafe(value: Short?): UShort? = value?.toUShort()
        fun Byte.byteImplicit(): UShort = toUShort()
        fun Short.shortImplicit(): UShort = toUShort()
        fun Byte.byteThis(): UShort = this.toUShort()
        fun Short.shortThis(): UShort = this.toUShort()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)

            for name in [
                "byteExplicit", "shortExplicit", "byteSafe", "shortSafe",
                "byteImplicit", "shortImplicit", "byteThis", "shortThis",
            ] {
                let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
                let calls = body.compactMap { instruction -> String? in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                    return ctx.interner.resolve(callee)
                }
                #expect(calls.filter { $0 == "kk_int_to_ushort" }.count == 1, "\(name): \(calls)")
                #expect(!calls.contains("toUShort"), "\(name) must not emit an unresolved conversion")
            }
        }
    }

    @Test
    func testImplicitSmallIntegerConversionsBindAndLowerToRealBridgesOrCopies() throws {
        let source = """
        fun Byte.byteInt(): Int = toInt()
        fun Byte.byteShort(): Short = toShort()
        fun Byte.byteUnsigned(): UInt = toUInt()
        fun Byte.byteFloat(): Float = toFloat()
        fun Short.shortInt(): Int = toInt()
        fun Short.shortByte(): Byte = toByte()
        fun Short.shortDouble(): Double = toDouble()
        fun Short.shortUByte(): UByte = toUByte()
        """
        let expectedLinks: [(function: String, link: String?)] = [
            ("byteInt", nil),
            ("byteShort", nil),
            ("byteUnsigned", "kk_int_to_uint"),
            ("byteFloat", "kk_int_to_float"),
            ("shortInt", nil),
            ("shortByte", "kk_int_to_byte"),
            ("shortDouble", "kk_int_to_double_bits"),
            ("shortUByte", "kk_int_to_ubyte"),
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
        for source in [
            "fun Boolean.invalid(): Int = toInt()",
            "fun Byte.invalidArity(): UInt = toUInt(1)",
        ] {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)
                #expect(ctx.diagnostics.hasError, "\(source) must remain invalid")
                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(!errors.isEmpty, "\(source) must be rejected")
            }
        }
    }
}
#endif
