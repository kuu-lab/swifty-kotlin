#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Regression coverage for KSP-466: `/` and `%` on ULong performed plain signed
/// Int64 division/modulo, which is wrong once a value's high bit is set (any
/// ULong >= 2^63) — e.g. `17663719463477156090uL / 2uL` printed
/// `18055231768593353853` instead of `8831859731738578045`. UInt does not
/// exhibit the bug because it is always zero-extended into the shared 64-bit
/// container. This is the same root-cause family as the ULong comparison/
/// toString sign-misinterpretation bug.
@Suite
struct CodegenBackendUnsignedDivisionAndModuloTests {

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testUnsignedDivisionAndModuloHighBitSetULong() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println(big / 2uL)
            println(big % 7uL)
            println(big % 1000uL)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloHighBitSetULong",
            expected: """
            8831859731738578045
            0
            90
            """ + "\n"
        )
    }

    @Test
    func testUnsignedDivisionAndModuloULongMaxValueBoundary() throws {
        let source = """
        fun main() {
            println(ULong.MAX_VALUE / 1uL)
            println(ULong.MAX_VALUE / ULong.MAX_VALUE)
            println(ULong.MAX_VALUE % ULong.MAX_VALUE)
            val big: ULong = 17663719463477156090uL
            println(ULong.MAX_VALUE / big)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloULongMaxValueBoundary",
            expected: """
            18446744073709551615
            1
            0
            1
            """ + "\n"
        )
    }

    @Test
    func testUnsignedDivisionAndModuloMemberCallForms() throws {
        // div()/rem()/floorDiv()/mod() are explicit member-call forms of the
        // same operators, lowered through a separate CallLowerer code path
        // (CallLowerer+PrimitiveMemberCalls.swift) that already routed to
        // kk_op_udiv/kk_op_urem before this fix -- lock in that they agree
        // with the infix operators for a high-bit-set value.
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println(big.div(2uL))
            println(big.rem(7uL))
            println(big.floorDiv(2uL))
            println(big.mod(7uL))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloMemberCallForms",
            expected: """
            8831859731738578045
            0
            8831859731738578045
            0
            """ + "\n"
        )
    }

    @Test
    func testUnsignedCompoundAssignDivisionAndModulo() throws {
        let source = """
        fun main() {
            var big: ULong = 17663719463477156090uL
            big /= 2uL
            println(big)
            var big2: ULong = 17663719463477156090uL
            big2 %= 1000uL
            println(big2)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedCompoundAssignDivisionAndModulo",
            expected: """
            8831859731738578045
            90
            """ + "\n"
        )
    }

    @Test
    func testUnsignedArrayElementCompoundAssignDivisionAndModulo() throws {
        let source = """
        fun main() {
            val values = ulongArrayOf(17663719463477156090uL)
            values[0] /= 2uL
            println(values[0])
            values[0] = 17663719463477156090uL
            values[0] %= 1000uL
            println(values[0])
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedArrayElementCompoundAssignDivisionAndModulo",
            expected: """
            8831859731738578045
            90
            """ + "\n"
        )
    }

    @Test
    func testUnsignedDivisionAndModuloByZeroThrows() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            val zero: ULong = 0uL
            try {
                println(big / zero)
            } catch (e: ArithmeticException) {
                println("ulong div: ArithmeticException")
            }
            try {
                println(big % zero)
            } catch (e: ArithmeticException) {
                println("ulong rem: ArithmeticException")
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloByZeroThrows",
            expected: """
            ulong div: ArithmeticException
            ulong rem: ArithmeticException
            """ + "\n"
        )
    }

    @Test
    func testUnsignedDivisionAndModuloUIntUnaffected() throws {
        // UInt is zero-extended into the shared 64-bit container, so it never
        // exhibited this bug -- this test locks in that the fix leaves it correct.
        let source = """
        fun main() {
            val small: UInt = 17u
            val big: UInt = UInt.MAX_VALUE
            println(big / small)
            println(big % small)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloUIntUnaffected",
            expected: """
            252645135
            0
            """ + "\n"
        )
    }
}

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}
#endif
