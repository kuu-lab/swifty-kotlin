@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    @Test
    func testSuspendFunInterfaceBoundReferenceCreatesSuspendVirtualThunk() throws {
        let source = """
        fun interface SuspendRunnable { suspend fun invoke() }

        fun main() {
            val runnable = SuspendRunnable { }
            val block: suspend () -> Unit = runnable::invoke
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let options = CompilerOptions(
                moduleName: "SuspendFunInterfaceBoundReferenceKIR",
                inputs: [userPath],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: TargetTriple.hostDefault(),
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let hasSuspendDispatchThunk = module.arena.declarations.contains { declaration in
                guard case let .function(function) = declaration,
                      function.isSuspend,
                      ctx.interner.resolve(function.name) == "invoke"
                else {
                    return false
                }
                return function.body.contains { instruction in
                    if case .virtualCall = instruction { return true }
                    return false
                }
            }
            #expect(hasSuspendDispatchThunk)
        }
    }

    /// A bound suspend reference to a fun-interface method must keep virtual dispatch.
    @Test
    func testFunInterfaceSuspendInvokeBoundReferenceStartsCoroutine() throws {
        let artifactPath = try testStdlibArtifactPath()
        let source = """
        import kotlin.coroutines.*

        fun interface SuspendRunnable { suspend fun invoke() }

        fun main() {
            var result = ""
            val runnable = SuspendRunnable { result = "OK" }
            val direct: suspend () -> Unit = { runnable.invoke() }
            val completion = Continuation<Unit>(EmptyCoroutineContext) { it.getOrThrow() }

            direct.startCoroutine(completion)
            println(result)

            result = ""
            runnable::invoke.startCoroutine(completion)
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "FunInterfaceSuspendInvokeBoundReference",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "OK\nOK\n"
            )
        }
    }

    /// Nominal FunctionN implementations adapt to suspend extension and regular function types.
    @Test
    func testNominalFunctionClassesAdaptToSuspendFunctionTypes() throws {
        let artifactPath = try testStdlibArtifactPath()
        let source = """
        import kotlin.coroutines.*

        private var result = ""

        private fun runSuspend(block: suspend Int.() -> Unit) {
            block.startCoroutine(1, Continuation(EmptyCoroutineContext) { it.getOrThrow() })
        }

        class ExtensionAction : Int.() -> Unit {
            override fun invoke(p1: Int) {
                result += "O"
                println("O")
            }
        }

        class RegularAction : (Int) -> Unit {
            override fun invoke(p1: Int) { result += "K" }
        }

        fun main() {
            val extensionAction = ExtensionAction()
            val regularAction = RegularAction()
            1.(ExtensionAction())()
            runSuspend(extensionAction)
            runSuspend(regularAction)
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "NominalSuspendFunctionTypes",
                emit: .executable, outputPath: outputBase,
                includeStdlib: false, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            do {
                try CodegenPhase().run(ctx)
            } catch {
                throw CompilerPipelineError.invalidInput(
                    "Codegen failed: \(error); diagnostics: \(ctx.diagnostics.diagnostics)"
                )
            }
            do {
                try LinkPhase().run(ctx)
            } catch {
                throw CompilerPipelineError.invalidInput(
                    "Link failed: \(error); diagnostics: \(ctx.diagnostics.diagnostics)"
                )
            }

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "O\nO\nOOK\n")
        }
    }

    /// KUU-3330: a resumed suspend call returning Unit must preserve the boxed
    /// Unit value when its result crosses an Any? assignment.
    @Test(arguments: [0, 2])
    func testSuspendUnitResultIsBoxedAfterResume(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3330_suspend_unit_after_resume.kt", file: #filePath),
            expectedOutput: "result=kotlin.Unit done=true\n",
            moduleName: "KUU3330SuspendUnitAfterResume",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    /// KUU-3405: a custom setter assignment must still run when it is the
    /// final statement of a suspend lambda after resuming from suspension.
    @Test
    func testFinalSuspendLambdaAssignmentInvokesCustomSetter() throws {
        let artifactPath = try testStdlibArtifactPath()
        let source = """
        import kotlin.coroutines.*
        import kotlin.coroutines.intrinsics.*

        private suspend fun suspendHere(): String = suspendCoroutineUninterceptedOrReturn { continuation ->
            continuation.resume("OK")
            COROUTINE_SUSPENDED
        }

        private fun builder(block: suspend () -> Unit) {
            block.startCoroutine(Continuation(EmptyCoroutineContext) {})
        }

        var setterCalls = 0
        var varWithCustomSetter: String = ""
            set(value) {
                setterCalls++
                field = value
            }

        fun main() {
            builder {
                if (suspendHere() != "OK") println("fail5")
                varWithCustomSetter = "OK"
            }
            println("$varWithCustomSetter:$setterCalls")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KUU3405FinalSuspendLambdaSetterAssignment",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            do {
                try CodegenPhase().run(ctx)
            } catch {
                throw CompilerPipelineError.invalidInput(
                    "Codegen failed: \(error); diagnostics: \(ctx.diagnostics.diagnostics)"
                )
            }
            do {
                try LinkPhase().run(ctx)
            } catch {
                throw CompilerPipelineError.invalidInput(
                    "Link failed: \(error); diagnostics: \(ctx.diagnostics.diagnostics)"
                )
            }

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "OK:1\n",
                "stderr: \(result.stderr)"
            )
        }
    }

    /// Suspend function references passed to startCoroutine must reuse the
    /// started continuation instead of intercepting an adapter frame as well.
    @Test
    func testSuspendFunctionReferenceStartCoroutineInterceptsOnce() throws {
        let artifactPath = try testStdlibArtifactPath()
        let source = """
        import kotlin.coroutines.*

        private class CountingInterceptor : ContinuationInterceptor {
            override val key: CoroutineContext.Key<*> = ContinuationInterceptor.Key
            var calls = 0
            override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> {
                calls++
                return continuation
            }
        }

        private suspend fun immediate(): Int = suspendCoroutine { it.resume(42) }

        fun main() {
            val interceptor = CountingInterceptor()
            val completion = Continuation<Int>(interceptor) { result ->
                println(if (result.isSuccess) "value:${result.getOrThrow()}" else "failed")
            }
            (::immediate).startCoroutine(completion)
            println("intercepts:${interceptor.calls}")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "SuspendFunctionReferenceInterceptor",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == "value:42\nintercepts:1\n"
            )
        }
    }

    /// KUU-2923: versioned parameters must not corrupt suspend member references.
    @Test
    func testIntroducedAtSuspendMemberReferencesRunThroughCoroutine() throws {
        let artifactPath = try testStdlibArtifactPath()
        let source = """
        @file:OptIn(ExperimentalVersionOverloading::class)

        import kotlin.coroutines.Continuation
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlin.coroutines.startCoroutine

        class SuspendVersionedHolder {
            suspend fun member(
                value: String = "O",
                @IntroducedAt("1") suffix: String = "K",
            ): String = value + suffix
        }

        suspend fun String.suspendExtension(
            @IntroducedAt("1") suffix: String = "K",
        ): String = this + suffix

        fun <T> runSuspendVersioned(block: suspend () -> T): T {
            var result: Result<T>? = null
            block.startCoroutine(Continuation(EmptyCoroutineContext) { result = it })
            return result!!.getOrThrow()
        }

        fun main() {
            val holder = SuspendVersionedHolder()
            println(runSuspendVersioned { holder.member() })
            println(runSuspendVersioned { with(holder) { "A".suspendExtension() } })

            val memberReference: suspend (SuspendVersionedHolder, String, String) -> String =
                SuspendVersionedHolder::member
            println(runSuspendVersioned { memberReference(holder, "O", "K") })

            val boundMemberReference: suspend (String, String) -> String = holder::member
            println(runSuspendVersioned { boundMemberReference("O", "K") })

            val extensionReference: suspend (String, String) -> String = String::suspendExtension
            println(runSuspendVersioned { extensionReference("O", "K") })
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "IntroducedAtSuspendMemberReferences",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "OK\nAK\nOK\nOK\nOK\n",
                "stderr: \(result.stderr)"
            )
        }
    }

    /// KUU-2118: an inline resume delivered before COROUTINE_SUSPENDED must
    /// continue through if and loop conditions before startCoroutine returns.
    @Test
    func testSuspendCallsInControlFlowConditionsResumeInline() throws {
        let artifactPath = try testStdlibArtifactPath()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/suspend_control_flow_condition_immediate_resume.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "SuspendControlFlowConditionImmediateResume",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == "if-true:if-false:while:while:do:do\n"
            )
        }
    }

    /// KUU-2119: suspend calls in a for-loop body resume before startCoroutine returns.
    @Test
    func testSuspendCallsInForBodiesResumeInline() throws {
        let artifactPath = try testStdlibArtifactPath()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/coroutine_suspend_in_for_body.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "CoroutineSuspendInForBody",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == "OK.|OK.|#20#25#30.\n"
            )
        }
    }

    /// KUU-2120: inline resumes must preserve loop exits, finally blocks, and continues.
    @Test
    func testSuspendCallsAcrossLoopBreakContinueResumeInline() throws {
        let artifactPath = try testStdlibArtifactPath()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/coroutine_suspend_break_continue.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "SuspendBreakContinueControlFlow",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == "OQW.\nabiof.\no1xo2\nAasBb.\n"
            )
        }
    }

    /// KUU-1022: interface bridges must preserve source overrides and captures.
    @Test(arguments: [false, true])
    func testCoroutineContextOverrideDispatch(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/coroutine_context_override_dispatch.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "CoroutineContextOverrideDispatch",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "0\ntrue\ntrue\ntrue\ntrue\n13\ntrue\ntrue\ninherited plus\n16\ntrue\ntrue\ntrue\ntrue\nstart:item:item\nfold override\nplus override\nplus override\nplus override\ntrue\n")
        }
    }

    @Test(arguments: [false, true])
    func testContinuationContextOverrides(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/continuation_context_override.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "ContinuationContextOverrides",
                emit: .executable, outputPath: outputBase,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "true\ngetter\ntrue\ntrue\ntrue\n7\n42\n")
        }
    }

    @Test(arguments: [false, true])
    func testContinuationInterceptorThroughPrecompiledStdlibArtifact(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ContinuationInterceptorArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            let expected = String(repeating: "true\n", count: 15) + "resumed\ndefault released\n1\n"
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
        }
    }

    @Test
    func testNativeDispatcherInterceptorThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.Dispatchers

        class Done : Continuation<Unit> {
            override val context: CoroutineContext = EmptyCoroutineContext
            override fun resumeWith(result: Result<Unit>) {}
        }
        fun main() {
            val original = Done()
            val direct = Dispatchers.Default.interceptContinuation(original)
            val interceptor: ContinuationInterceptor = Dispatchers.Default
            val indirect = interceptor.interceptContinuation(original)
            println(direct === indirect)
            interceptor.releaseInterceptedContinuation(indirect)
            println("released")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "NativeInterceptorArtifact",
                emit: .executable, outputPath: outputBase,
                includeStdlib: false, stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "true\nreleased\n")
        }
    }

    @Test(arguments: [false, true])
    func testDispatcherNames(useArtifact: Bool) throws {
        TestStdlibCache.shared.prepare()
        let artifactPath = useArtifact ? CompilerOptions.defaultStdlibLibraryPath : nil
        if useArtifact {
            try #require(artifactPath != nil, "shared stdlib artifact must be available")
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/dispatchers_to_string.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "DispatcherNames",
                emit: .executable, outputPath: outputBase,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            let expected = """
            Dispatchers.IO
            Dispatchers.Unconfined
            Dispatchers.Default
            Dispatchers.IO
            Dispatchers.Unconfined
            Dispatchers.Default
            Dispatchers.IO
            Dispatchers.Unconfined
            Dispatchers.Default
            [Dispatchers.IO, Dispatchers.Unconfined, Dispatchers.Default]
            false
            false
            true
            1263223809
            1263223810
            1263223812
            [1263223809, 1263223810, 1263223812]
            io
            unconfined
            Dispatchers.IO
            true
            Dispatchers.Unconfined
            true
            true

            """
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
        }
    }

    /// KSP-1151: source-backed coroutine intrinsic fallbacks must not leave a
    /// direct reference to the Kotlin parameter `function` in the stdlib
    /// artifact. A trivial artifact consumer is enough to exercise the native
    /// linker against every object emitted by the stdlib-only build.
    @Test
    func testCoroutineIntrinsicFallbackThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun main() {
            println("ok")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "CoroutineIntrinsicArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "ok\n")
        }
    }
}
