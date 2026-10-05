#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AdvancedTypeInferenceTests {
    @Test(arguments: [
        "sequence { for (value in 0 until 3) yield(value) }",
        "sequence<Int> { for (value in 0 until 3) yield(value) }",
        "sequence { for (value in 0..2) this.yield(value) }",
        "sequence { val value = 7; yield(value) }",
        "sequence { for (value in listOf(1, 2)) yieldAll(listOf(value)) }",
        "sequence { for (value in 0 until 2) { for (value in 2 until 3) yield(value) } }",
        "iterator { for (value in 0 until 3) yield(value) }",
        "iterator<Int> { val value = 7; yield(value) }",
    ])
    func testSequenceBuilderBootstrapUsesLambdaScope(builder: String) throws {
        let source = """
        fun demo() {
            val value = "outer"
            val values = \(builder)
            val result: Int = values.\(builder.hasPrefix("iterator") ? "next" : "first")()
            val untouched: String = value
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ["sequence", "iterator"].contains(ctx.interner.resolve(name))
            })
            let type = try #require(sema.bindings.exprType(for: call))
            guard case let .classType(classType) = sema.types.kind(of: type) else {
                Issue.record("Expected a builder collection type")
                return
            }
            #expect(classType.args.first == .out(sema.types.intType))
        }
    }

    @Test(arguments: [
        "val values: Sequence<String> = sequence { for (value in 0 until 3) yield(value) }",
        "val values = sequence<String> { for (value in 0 until 3) yield(value) }",
        "val values = iterator<String> { val value = 1; yield(value) }",
        "val values = sequence { yield(missingBuilderValue) }",
    ])
    func testSequenceBuilderBootstrapPreservesRealErrors(statement: String) throws {
        let ctx = makeContextFromSource("fun demo() { \(statement) }")
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func testSequenceBuilderBootstrapKeepsNullableElementType() throws {
        let ctx = makeContextFromSource("""
        fun demo() {
            val value = "outer"
            val values = sequence { val value: Int? = null; yield(value) }
            val result: Int? = values.first()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func testGenericCollectionReceiverLambdaInfersWithoutAnnotation() throws {
        let source = """
        fun <T> collect(builderAction: MutableList<T>.() -> Unit): List<T> = buildList<T>(builderAction)

        fun demo(): Int {
            val xs = collect {
                add(1)
                add(2)
            }
            return xs[0]
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
        #expect(!ctx.diagnostics.hasError, "Expected collect's receiver lambda to infer T from add(), got: \(diagnostics)")
    }

    @Test func testSequenceBuilderYieldAllListChoosesIterableOverload() throws {
        let source = """
        fun values(): List<Int> = sequence {
            yieldAll(listOf(1, 2))
        }.toList()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
        #expect(!ctx.diagnostics.hasError, "Expected yieldAll(List<Int>) to select Iterable<T>, got: \(diagnostics)")
    }

    @Test(arguments: [
        ("MutableList<T>", "List<T>", "buildList<T>(action)", "add(1); add(2)", "xs[0]"),
        ("MutableSet<T>", "Set<T>", "buildSet<T>(action)", "add(1); add(2)", "xs.first()"),
        ("MutableMap<String, T>", "Map<String, T>", "TODO()", "put(\"one\", 1)", "xs.getValue(\"one\")"),
    ])
    func testGenericCollectionBuildersUseMutationInference(
        receiver: String, result: String, implementation: String, body: String, access: String
    ) throws {
        let source = """
        fun <T> gather(action: \(receiver).() -> Unit): \(result) = \(implementation)
        fun demo(): Int {
            val xs = gather { \(body) }
            return \(access)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "gather"
            })
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(binding.substitutedTypeArguments == [sema.types.intType])
        }
    }

    @Test func testExperimentalTypeInferenceInfersCustomBuilderElementTypeWithoutExpectedType() throws {
        let source = """
        import kotlin.experimental.ExperimentalTypeInference

        @ExperimentalTypeInference
        fun <T> collect(builderAction: MutableList<T>.() -> Unit): List<T> = TODO()

        fun demo(): Int {
            val xs = collect {
                add(1)
                add(2)
            }
            return xs[0]
        }
        """

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt")
            .path
        let ctx = makeCompilationContext(
            inputs: [path],
            frontendFlags: [
                "new-inference",
                "unrestricted-builder-inference",
                "ProperTypeInferenceConstraintsProcessing",
            ]
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))

        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected custom builder inference to succeed, got: \(diagnostics)"
        )
    }

    @Test func testGenericCollectionBuilderPreservesOtherTypeEvidence() throws {
        let ctx = makeContextFromSource("""
        fun <T> gather(action: MutableList<T>.() -> Unit): List<T> = buildList<T>(action)
        fun <T> gatherSeed(seed: T, action: MutableList<T>.() -> Unit): List<T> = buildList<T>(action)
        fun demo() {
            val fromSeed = gatherSeed(1) {}
            val seedAndMutation = gatherSeed(1) { add(2) }
            val expected: List<Int> = gather {}
            val explicit = gather<Int> { add(3) }
            val checkedSeed: List<Int> = fromSeed
            val checkedMutation: List<Int> = seedAndMutation
            val checkedExplicit: List<Int> = explicit
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func testBuildListWithNamedCapacityArgumentInfersElementType() throws {
        let source = """
        fun demo(): List<Int> {
            return buildList(capacity = 10) {
                add(1)
                add(2)
            }
        }
        """

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt")
            .path
        let ctx = makeCompilationContext(
            inputs: [path],
            frontendFlags: [
                "new-inference",
                "unrestricted-builder-inference",
                "ProperTypeInferenceConstraintsProcessing",
            ]
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))

        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected buildList(capacity = ...) with named argument to infer element type, got: \(diagnostics)"
        )
    }

    @Test func testBuildListWithNonLambdaArgumentReportsNoViableOverload() throws {
        let source = """
        fun demo() {
            buildList(1)
        }
        """

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt")
            .path
        let ctx = makeCompilationContext(
            inputs: [path],
            frontendFlags: [
                "new-inference",
                "unrestricted-builder-inference",
                "ProperTypeInferenceConstraintsProcessing",
            ]
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))

        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            ctx.diagnostics.hasError,
            "Expected buildList(1) to report a no-viable-overload error, got: \(diagnostics)"
        )
    }

    @Test func testExperimentalTypeInferenceAnnotationIsAvailableWithoutCompilerFlags() throws {
        let source = """
        import kotlin.experimental.ExperimentalTypeInference

        @ExperimentalTypeInference
        fun <T> annotatedCollect(builderAction: MutableList<T>.() -> Unit): List<T> = TODO()

        fun demo() {}
        """

        let ctx = makeContextFromSource(source)

        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected annotation-driven builder inference to succeed, got: \(diagnostics)"
        )
    }
}
#endif
