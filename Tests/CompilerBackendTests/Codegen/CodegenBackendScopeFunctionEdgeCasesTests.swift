#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendScopeFunctionEdgeCasesTests {

    @Test
    func testInheritedContextMemberExtensionInsideRunLambda() throws {
        let runLibrary = """
        package testlib
        public inline fun <T, R> T.run(block: T.() -> R): R = block()
        public inline fun <T, R> with(receiver: T, block: T.() -> R): R = receiver.block()
        """
        let libraryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let libraryPath = libraryBase + ".kklib"
        defer { try? FileManager.default.removeItem(atPath: libraryPath) }

        try withTemporaryFile(contents: runLibrary) { path in
            let options = CompilerOptions(
                moduleName: "KUU3357RunLibrary",
                inputs: [path],
                outputPath: libraryBase,
                emit: .library,
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
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
        }

        let source = """
        @file:OptIn(kotlin.ExperimentalContextParameters::class)
        import testlib.run
        import testlib.with

        abstract class A {
            context(c: C) fun P.foo(): Int = c.result
        }

        class B : A() {
            val p = P()
            context(c: C) fun test(): Int = p.run { foo() }
        }

        class P
        class C(val result: Int)

        fun main() {
            val result = with(C(42)) { B().test() }
            if (result != 42) {
                val failure: Any? = null
                failure!!
            }
        }
        """

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: outputPath) }
        try withTemporaryFile(contents: source) { path in
            let options = CompilerOptions(
                moduleName: "InheritedContextMemberExtensionInsideRunLambda",
                inputs: [path],
                outputPath: outputPath,
                emit: .executable,
                searchPaths: [libraryPath],
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
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
        }
    }

    @Test
    func testNamedArgumentCallKeepsMultipleContextParameters() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        context(a: String, b: Int)
        fun f(x: Int = 0) = "$a$b$x"

        @OptIn(ExperimentalContextParameters::class)
        fun main() {
            with("S") { with(4) { println(f(x = 2)) } }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NamedArgumentMultipleContextParameters",
            expected: "S42\n"
        )
    }

    @Test
    func testGenericMemberContextParametersUseSubstitutedClassTypeArguments() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        class Box<E>(val x: E)

        @OptIn(ExperimentalContextParameters::class)
        class A<X, Y : Number> {
            context(box: Box<X>, y: Y)
            fun foo(): String = box.x.toString() + y.toString()
        }

        @OptIn(ExperimentalContextParameters::class)
        fun main() {
            with(Box("OK")) {
                with(56) {
                    println(A<String, Int>().foo())
                }
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericMemberContextParameters",
            expected: "OK56\n"
        )
    }

    @Test(arguments: [true, false])
    func testTailPositionLabeledReturnPropagatesValue(defaultStdlib: Bool) throws {
        let source = """
        fun main() {
            val r = run { return@run 9 }
            println(r)
            println(run { return@run 9 })
            println(run(foo@{ return@foo 7 }))
            println(run { return@run "tail" })
            println(run<Int?> { return@run null })
            println(run { return@run 2147483648L })
            println("x".let { return@let 4 })
            println(with(0) { return@with "w" })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TailLabeledReturnValue",
            expected:
                """
                9
                9
                7
                tail
                null
                2147483648
                4
                w
                """
                + "\n",
            allowDefaultStdlibLibrary: defaultStdlib
        )
    }

    @Test
    func testCodegenCompilesContextHelper() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun main() {
            val result = context("context-ok") { contextOf<String>() }
            println(result)
            println(context("context-two", 2) { contextOf<String>() })
            println(context(1, 2, "context-six", 4, 5, 6) { contextOf<String>() })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ContextHelper",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                ==
                """
                context-ok
                context-two
                context-six
                """
                + "\n"
            )
        }
    }

    @Test
    func testCrossinlineWrapperCapturesContextParameter() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        context(s: String)
        fun foo() = s

        fun bar(f: () -> String) = f()

        inline fun baz(crossinline f: () -> String) = bar { f() }

        @OptIn(ExperimentalContextParameters::class)
        context(_: String)
        fun qux() = baz { foo() }

        @OptIn(ExperimentalContextParameters::class)
        fun main() {
            println(context("OK") { qux() })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CrossinlineContextParameterCapture",
            expected: "OK\n"
        )
    }

    @Test
    func testO2ContextFunctionInvokeUsesContextReceiverArity() throws {
        let wrappers = [1, 22].map { arity in
            let types = (0 ..< arity).map { "T\($0)" }
            let values = (0 ..< arity).map { "v\($0)" }
            let typeParameters = (types + ["R"]).joined(separator: ", ")
            let valueParameters = (0 ..< arity)
                .map { "v\($0): T\($0)" }
                .joined(separator: ", ")
            let contextTypes = types.joined(separator: ", ")
            let contextValues = values.joined(separator: ", ")
            return """
            inline fun <\(typeParameters)> context\(arity)(
                \(valueParameters),
                block: context(\(contextTypes)) () -> R
            ): R = block(\(contextValues))
            """
        }
        let source = wrappers.joined(separator: "\n") + "\nfun main() {}\n"

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "ContextFunctionInvokeArity",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable,
                target: TargetTriple.hostDefault(),
                optLevel: .O2,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false,
                entryPointFQName: "main"
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try CompilerTestSupport.runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testCodegenCompilesNamedContextParametersAndAccessors() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        var seen = ""

        @OptIn(ExperimentalContextParameters::class)
        context(prefix: String)
        fun render(value: String): String = prefix + value

        @OptIn(ExperimentalContextParameters::class)
        context(prefix: String)
        fun renderIndex(value: Int): String = prefix + value

        @OptIn(ExperimentalContextParameters::class)
        context(prefix: String)
        fun contextualValue(): String = prefix

        object ContextCallableTarget {
            @OptIn(ExperimentalContextParameters::class)
            context(prefix: String, suffix: Char)
            fun contextualValue(): String = prefix + suffix
        }

        @OptIn(ExperimentalContextParameters::class)
        context(index: Int)
        fun selected(values: Array<String>): String = values[index]

        @OptIn(ExperimentalContextParameters::class)
        context(prefix: String)
        var current: String
            get() = prefix
            set(value) { seen = prefix + value }

        class ContextHolder {
            @OptIn(ExperimentalContextParameters::class)
            context(prefix: String)
            fun render(value: String): String = prefix + value

            @OptIn(ExperimentalContextParameters::class)
            context(prefix: String)
            var current: String
                get() = prefix
                set(value) { seen = prefix + value }
        }

        @OptIn(ExperimentalContextParameters::class)
        fun main() {
            context(prefix: String)
            fun localRender(value: String): String = prefix + value

            println(context("I") { render("K") })
            println(context(1) { selected(arrayOf("A", "B")) })
            println(context("L") { localRender("K") })
            val renderRef: context(String) (String) -> String = ::render
            println(context("C") { renderRef("K") })
            context("R") {
                val boundContextRef: () -> String = ::contextualValue
                println(boundContextRef())
            }
            context("O", 'K') {
                val memberContextRef: () -> String = ContextCallableTarget::contextualValue
                println(memberContextRef())
            }
            context("H") {
                println(listOf(1).map(::renderIndex))
            }
            val holder = ContextHolder()
            println(context("M") { holder.render("K") })
            context("O") {
                current = "K"
                println(current)
                println(seen)
            }
            context("P") {
                holder.current = "K"
                println(holder.current)
                println(seen)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "NamedContextParameters",
                emit: .executable,
                outputPath: outputBase
            )
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                ==
                """
                IK
                B
                LK
                CK
                R
                OK
                [H1]
                MK
                O
                OK
                P
                PK
                """
                + "\n"
            )
        }
    }
}
#endif
