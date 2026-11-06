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
    func nullableLambdaResultOnElvisLeftKeepsNullableTypeParameter() throws {
        // KUU-4279: `x?.let { ... nullable body ... } ?: fallback` must let the
        // scope function's result type parameter resolve to `T?`. Seeding the
        // lambda's expected return type with the non-null Elvis expected type
        // rejected a legitimately nullable body with SEMA-0469.
        let source = """
            package elvisLhsNullableLambdaResult
            fun <T, R> T.myLet(block: (T) -> R): R = block(this)
            class Holder {
                var hourOfAmPm: Int? = null
                var amPm: String? = null
                fun toHour(): Int {
                    val hour: Int = amPm?.myLet { amPm ->
                        hourOfAmPm?.myLet { hourOfAmPm ->
                            hourOfAmPm.myLet { hour -> if (hour == 12) 0 else hour }
                        }
                    } ?: 0
                    return hour
                }
                fun direct(value: Int?, other: Int?): Int {
                    val result: Int = value?.myLet { other } ?: 0
                    return result
                }
                fun nonSafe(value: Int, other: Int?): Int {
                    val result: Int = value.myLet { other } ?: 0
                    return result
                }
            }
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let diagnostics = diagnosticsForPath(path, in: ctx)
            let errors = diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "got: \(errors.map { "\($0.code): \($0.message)" })")
        }
    }

    /// KUU-4354: invoking a function-typed parameter on the Elvis LHS must
    /// accept its nullable result under the non-null expected type —
    /// `f() ?: d` is `T`, not a `T? <: T` constraint failure. A genuinely
    /// incompatible result is still rejected.
    @Test
    func functionValueInvokeOnElvisLeftAcceptsNullableResult() throws {
        let source = """
            package elvisLhsFunctionValue
            fun <T> fallback(f: () -> T?, d: T): T = f() ?: d
            fun concrete(f: () -> Int?, d: Int): Int = f() ?: d
            fun <T> bothNullable(f: () -> T?, d: T?): T? = f() ?: d
            fun <T> nonNullResult(f: () -> T, d: T): T = f() ?: d
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "got: \(errors.map { "\($0.code): \($0.message)" })")
        }
    }

    @Test
    func functionValueInvokeOnElvisLeftStillRejectsIncompatibleResult() throws {
        let source = """
            package elvisLhsFunctionValueReject
            fun bad(f: () -> Int?, d: String): String = f() ?: d
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(!errors.isEmpty)
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
