#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

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

@Suite
struct CodegenBackendMathOverloadEdgeCasesTests {

    @Test
    func testCodegenCompilesMathOverloadEdgeCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            val sqrtFloat: Float = sqrt(9.0f)
            val sqrtDouble: Double = sqrt(9.0)
            println(sqrtFloat)
            println(sqrtDouble)

            val absInt: Int = abs(-7)
            val absLong: Long = abs(-9L)
            val absFloat: Float = abs(-3.5f)
            val absDouble: Double = abs(-4.5)
            println(absInt)
            println(absLong)
            println(absFloat)
            println(absDouble)

            val atan2Float: Float = atan2(1.0f, 1.0f)
            val atan2Double: Double = atan2(1.0, 1.0)
            println(atan2Float > 0.78f && atan2Float < 0.79f)
            println(atan2Double > 0.78 && atan2Double < 0.79)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MathOverloadEdgeCases",
            expected:
                """
                3.0
                3.0
                7
                9
                3.5
                4.5
                true
                true
                """
                + "\n"
        )
    }

    @Test
    func testCodegenMathExtensionPropertiesLowerToRuntimeHelpers() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            val i: Int = -7
            val l: Long = -9L
            val f: Float = -3.5f
            val d: Double = -4.5
            val oneF: Float = 1.0f
            val oneD: Double = 1.0
            val ai: Int = i.absoluteValue
            val al: Long = l.absoluteValue
            val af: Float = f.absoluteValue
            val ad: Double = d.absoluteValue
            val si: Int = i.sign
            val sl: Int = l.sign
            val sf: Float = f.sign
            val sd: Double = d.sign
            val uf: Float = oneF.ulp
            val ud: Double = oneD.ulp
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MathExtensionProperties", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (String, Int)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (ctx.interner.resolve(callee), arguments.count)
            }

            for expected in [
                "kk_float_ulp",
                "kk_double_ulp",
            ] {
                #expect(
                    calls.contains(where: { $0 == expected && $1 == 1 }),
                    "Expected \(expected) to lower with one receiver argument, got \(calls)"
                )
            }

            for extensionHelper in [
                "kk_float_ulp",
                "kk_double_ulp",
            ] {
                #expect(
                    !calls.contains(where: { $0 == extensionHelper && $1 == 0 }),
                    "Extension property helper \(extensionHelper) must not be emitted as a top-level initializer"
                )
            }
        }
    }

    // TEST-MATH-024: atan2・cbrt・双曲線関数の lowering を検証する
    // (既存の IEEErem/nextTowards/pow/withSign テストに対する対称性ギャップを補完)
    @Test
    func testCodegenMathSignedZeroSymmetryFunctionsLowerToRuntimeHelpers() throws {
        let source = """
        import kotlin.math.*

        fun sample(d: Double, f: Float) {
            val a2d = atan2(d, d)
            val a2f = atan2(f, f)
            val cbrtD = cbrt(d)
            val cbrtF = cbrt(f)
            val sinhD = sinh(d)
            val sinhF = sinh(f)
            val coshD = cosh(d)
            val coshF = cosh(f)
            val tanhD = tanh(d)
            val tanhF = tanh(f)
            val atanhD = atanh(d)
            val atanhF = atanh(f)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MathSignedZeroSymmetry", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sample", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }

            for expected in [
                "kk_math_atan2",
                "kk_math_atan2_float",
                "kk_math_cbrt",
                "kk_math_cbrt_float",
                "kk_math_sinh",
                "kk_math_sinh_float",
                "kk_math_cosh",
                "kk_math_cosh_float",
                "kk_math_tanh",
                "kk_math_tanh_float",
                "kk_math_atanh",
                "kk_math_atanh_float",
            ] {
                #expect(
                    calls.contains(expected),
                    "Expected \(expected) in lowered KIR, got \(calls)"
                )
            }
        }
    }

    @Test
    func testCodegenRemainingFloatingMathOverloadsLowerToRuntimeHelpers() throws {
        let source = """
        import kotlin.math.*

        fun sample(d: Double, f: Float, i: Int) {
            val ieeeD = d.IEEErem(d)
            val ieeeF = f.IEEErem(f)
            val nextD = d.nextTowards(d)
            val nextF = f.nextTowards(f)
            val powF = f.pow(f)
            val powDI = d.pow(i)
            val powFI = f.pow(i)
            val signD = d.withSign(d)
            val signDI = d.withSign(i)
            val signF = f.withSign(f)
            val signFI = f.withSign(i)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MathRemainingFloatingOverloads", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sample", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (String, Int)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (ctx.interner.resolve(callee), arguments.count)
            }

            for expected in [
                "kk_math_IEEErem",
                "kk_math_IEEErem_float",
                "kk_math_nextTowards",
                "kk_math_nextTowards_float",
                "kk_math_pow_float",
                "kk_math_pow_int",
                "kk_math_pow_float_int",
                "kk_math_withSign",
                "kk_math_withSign_int",
                "kk_math_withSign_float",
                "kk_math_withSign_float_int",
            ] {
                #expect(
                    calls.contains(where: { $0 == expected && $1 == 2 }),
                    "Expected \(expected) to lower with two arguments, got \(calls)"
                )
            }
        }
    }

    // PARITY-SEMA-003: kotlin.math.abs(x) called via FQN (no import) must lower identically to the import path.
    @Test
    func testCodegenFQNMathCallsLowerToRuntimeHelpers() throws {
        let source = """
        fun sample(i: Int, d: Double) {
            val absI = kotlin.math.abs(i)
            val absD = kotlin.math.abs(d)
            val sqrtD = kotlin.math.sqrt(d)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FQNMathCalls", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sample", in: module, interner: ctx.interner)
            let callees = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }

            #expect(callees.contains("kk_math_sqrt"), "FQN sqrt(Double) must lower to kk_math_sqrt, got \(callees)")
            // KSP-635: abs is bundled Kotlin source, so no runtime bridge is emitted.
            #expect(
                !callees.contains(where: { $0.hasPrefix("kk_math_abs") }),
                "FQN abs must not lower to a runtime bridge, got \(callees)"
            )
        }
    }

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
}
#endif
