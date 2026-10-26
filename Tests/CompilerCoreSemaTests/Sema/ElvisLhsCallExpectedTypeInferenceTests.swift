#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ElvisLhsCallExpectedTypeInferenceTests {
    @Test(arguments: [false, true])
    func nullableGenericInputCanFeedAnElvisWithNonNullContext(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        fun <T> identity(value: T): T = value
        fun test(value: Int?, values: List<Int?>) {
            val inferred: Any = identity(value) ?: "fallback"
            val explicit: Any = identity<Int?>(value) ?: "fallback"
            val fromReceiver: Any = values.firstOrNull() ?: "fallback"
            val text: String = identity("text") ?: "fallback"
            val direct: Int? = identity(value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func nullableGenericElvisStillRejectsAnIncompatibleResult() throws {
        let sources = [
            """
            package invalidElvisResult
            fun <T> identity(value: T): T = value
            fun test(value: Int?): String = identity(value) ?: 7
            """,
            """
            package invalidElvisMixedResult
            fun <T> identity(value: T): T = value
            fun test(value: Int?): String = identity(value) ?: "fallback"
            """,
            """
            package invalidDirectResult
            fun <T> identity(value: T): T = value
            fun test(value: Int?): String = identity(value)
            """,
            """
            package invalidInferredBound
            fun <T : Any> nonNull(value: T): T? = value
            fun test(value: Int?): Any = nonNull(value) ?: "fallback"
            """,
            """
            package invalidExplicitArgument
            fun <T> identity(value: T): T = value
            fun test(value: Int?): Any = identity<String>(value) ?: "fallback"
            """,
            """
            package invalidExplicitBound
            fun <T : Any> nonNull(value: T): T? = value
            fun test(value: Int?): Any = nonNull<Int?>(value) ?: "fallback"
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            for path in paths {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                #expect(diagnostics.contains { $0.severity == .error },
                    "Expected an error for \(path): \(diagnostics)")
            }
        }
    }

    @Test
    func genericCallOnElvisLeftUsesEnclosingExpectedType() throws {
        let sources = [
            """
            package elvisLhsGenericCall
            interface Node {
                fun <T : Node> child(code: Int): T? = null
            }
            class Branch : Node {
                fun parent(): Node = child(42) ?: this
                fun explicitParent(): Node = child<Node>(42) ?: this
                fun directParent(): Node? = child(42)
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            for path in paths {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: diagnostics)
            }
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "got: \(errors.map { "\($0.code): \($0.message)" })")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let childCalls = allExprIDs(in: ast, path: paths[0], ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "child"
            }
            #expect(childCalls.count == 3)
            let nodeSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("elvisLhsGenericCall"), ctx.interner.intern("Node"),
            ]))
            let nodeType = sema.types.make(.classType(ClassType(
                classSymbol: nodeSymbol, args: [], nullability: .nonNull
            )))
            let contextualCall = try #require(childCalls.first)
            let binding = try #require(sema.bindings.callBinding(for: contextualCall))
            #expect(binding.substitutedTypeArguments == [nodeType])
        }
    }

    @Test
    func genericCallWithoutExpectedTypeStillRejectsUnresolvedTypeArgument() throws {
        let source = """
            package elvisLhsUnresolved
            interface Node {
                fun <T : Node> child(code: Int): T? = null
            }
            fun unresolved(node: Node) = node.child(42)
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-INFER", in: diagnosticsForPath(path, in: ctx))
        }
    }
}
#endif
