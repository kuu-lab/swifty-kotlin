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
        irFlags: irFlags,
        stdlibLibraryPath: try testStdlibArtifactPath()
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
    func testCodegenMathExtensionPropertiesLowerToSourceBackedAccessors() throws {
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
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "MathExtensionProperties",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (String, Int)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (ctx.interner.resolve(callee), arguments.count)
            }

            // Property accessors in the artifact use the mangled JVM-style
            // `get` entry name rather than the Kotlin property name.  The
            // source has ten math property reads, each with one receiver.
            let artifactAccessors = calls.filter {
                $0.0.hasPrefix("kk_fn_get_") && $0.1 == 1
            }
            #expect(
                artifactAccessors.count == 10,
                "Expected ten imported math property accessors, got \(calls)"
            )

            for extensionHelper in [
                "absoluteValue",
                "sign",
                "ulp",
            ] {
                #expect(
                    !calls.contains(where: { $0 == extensionHelper && $1 == 0 }),
                    "Extension property helper \(extensionHelper) must not be emitted as a top-level initializer"
                )
            }

            for removedHelper in [
                "__kk_math_abs_int",
                "__kk_math_abs_long",
                "__kk_math_abs_float",
                "__kk_math_abs",
                "__kk_math_sign_int",
                "__kk_math_sign_long",
                "__kk_math_sign_float",
                "__kk_math_sign",
            ] {
                #expect(
                    !calls.contains(where: { $0.0 == removedHelper }),
                    "\(removedHelper) is Kotlin-source backed and must not be called, got \(calls)"
                )
            }
        }
    }

    @Test
    func testCodegenMathMinMaxOverloadsLowerToSourceBackedCalls() throws {
        let source = """
        import kotlin.math.*

        fun sample(
            d1: Double, d2: Double,
            f1: Float, f2: Float,
            i1: Int, i2: Int,
            l1: Long, l2: Long,
            ui1: UInt, ui2: UInt,
            ul1: ULong, ul2: ULong
        ) {
            val maxD = max(d1, d2)
            val maxF = max(f1, f2)
            val maxI = max(i1, i2)
            val maxL = max(l1, l2)
            val maxUI = max(ui1, ui2)
            val maxUL = max(ul1, ul2)
            val minD = min(d1, d2)
            val minF = min(f1, f2)
            val minI = min(i1, i2)
            val minL = min(l1, l2)
            val minUI = min(ui1, ui2)
            val minUL = min(ul1, ul2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "MathMinMaxOverloads",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sample", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (String, Int)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (ctx.interner.resolve(callee), arguments.count)
            }

            for expected in ["max", "min"] {
                #expect(
                    calls.filter { isKotlinCallee($0, named: expected) && $1 == 2 }.count == 6,
                    "Expected six source-backed \(expected) overload calls, got \(calls)"
                )
            }

            #expect(
                !calls.contains(where: { $0.0.hasPrefix("__kk_math_max") || $0.0.hasPrefix("__kk_math_min") }),
                "min/max are Kotlin-source backed and must not call __kk_math_* helpers, got \(calls)"
            )
        }
    }

    // TEST-MATH-024: atan2・cbrt・双曲線関数の source-wrapper lowering を検証する
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
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "MathSignedZeroSymmetry",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sample", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }

            for sourceFunction in [
                "atan2", "cbrt", "sinh", "cosh", "tanh", "atanh",
            ] {
                #expect(
                    calls.contains(where: { isKotlinCallee($0, named: sourceFunction) }),
                    "Expected the consumer call to remain source-backed as \(sourceFunction), got \(calls)"
                )
            }

            #expect(
                !calls.contains(where: { $0.hasPrefix("__kk_math_") }),
                "Consumer calls must use source-backed math declarations, got \(calls)"
            )
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
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "MathRemainingFloatingOverloads",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sample", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (String, Int)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (ctx.interner.resolve(callee), arguments.count)
            }

            for sourceFunction in ["IEEErem", "nextTowards", "pow"] {
                #expect(
                    calls.contains(where: { isKotlinCallee($0.0, named: sourceFunction) && $0.1 == 2 }),
                    "Expected the consumer call to remain source-backed as \(sourceFunction), got \(calls)"
                )
            }

            #expect(
                !calls.contains(where: { $0.0.hasPrefix("__kk_math_") }),
                "Consumer calls must use source-backed math declarations, got \(calls)"
            )
        }
    }

    // PARITY-SEMA-003: kotlin.math.abs(x) called via FQN (no import) must lower identically to the import path.
    @Test
    func testCodegenFQNMathCallsLowerLikeImportedCalls() throws {
        let source = """
        fun sample(i: Int, d: Double) {
            val absI = kotlin.math.abs(i)
            val absD = kotlin.math.abs(d)
            val sqrtD = kotlin.math.sqrt(d)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "FQNMathCalls",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "sample", in: module, interner: ctx.interner)
            let callees = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }

            #expect(
                callees.filter { isKotlinCallee($0, named: "abs") }.count == 2,
                "FQN abs(Int)/abs(Double) must lower to the Kotlin-source abs, got \(callees)"
            )
            #expect(containsKotlinCallee("sqrt", in: callees), "FQN sqrt(Double) must lower to the stdlib artifact, got \(callees)")
            #expect(
                !callees.contains(where: { $0.hasPrefix("__kk_math_") }),
                "FQN consumer calls must not bypass source-backed math declarations, got \(callees)"
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
