#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-3862: a statically `Iterable<T>`-typed receiver resolves the
/// `maxOf`/`minOf`/`maxOfOrNull`/`minOfOrNull` selector overloads through
/// the collection member fallback, which picked the first registered
/// candidate. `Iterable.maxOfOrNull` registers the `(T) -> Double`
/// overload before the generic `(T) -> R` one, so `xs.maxOfOrNull { it }`
/// bound the Double overload and Int selector results were unboxed as
/// Double bits (`3.0E-323`). The selector's inferred return type must
/// drive the choice: the non-generic `(T) -> Double` / `(T) -> Float`
/// overloads only when the selector returns that type, and the generic
/// `(T) -> R` overload for every other selector result.
@Suite
struct IterableExtremaSelectorBindingTests {
    /// What the bound overload's selector parameter must return.
    private enum SelectorReturn {
        /// The generic `(T) -> R` overload — the selector's return type is
        /// the callee's own type parameter.
        case generic
        case double
        case float
    }

    private static func expectSelectorReturn(
        _ want: SelectorReturn,
        callID: ExprID,
        calleeName: String,
        sema: SemaModule
    ) throws {
        let binding = try #require(
            sema.bindings.callBinding(for: callID),
            "\(calleeName): call must have a bound callee"
        )
        #expect(
            sema.symbols.isSourceBackedSymbol(binding.chosenCallee),
            "\(calleeName): must bind a bundled-source overload"
        )
        let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
        let lastParam = try #require(signature.parameterTypes.last)
        guard case let .functionType(fnType) = sema.types.kind(
            of: sema.types.makeNonNullable(lastParam)
        ) else {
            Issue.record("\(calleeName): selector parameter is not a function type")
            return
        }
        let selectorReturn = sema.types.makeNonNullable(fnType.returnType)
        switch want {
        case .generic:
            guard case .typeParam = sema.types.kind(of: selectorReturn) else {
                Issue.record(
                    "\(calleeName): expected the generic (T) -> R overload, got selector return \(sema.types.renderType(selectorReturn))"
                )
                return
            }
        case .double:
            #expect(
                selectorReturn == sema.types.doubleType,
                "\(calleeName): expected the (T) -> Double overload, got selector return \(sema.types.renderType(selectorReturn))"
            )
        case .float:
            #expect(
                selectorReturn == sema.types.floatType,
                "\(calleeName): expected the (T) -> Float overload, got selector return \(sema.types.renderType(selectorReturn))"
            )
        }
    }

    @Test
    func iterableMaxOfOrNullBindsOverloadBySelectorReturnType() throws {
        let source = """
        fun main() {
            val xs: Iterable<Int> = listOf(4, 5, 6)
            println(xs.maxOfOrNull { it })
            println(xs.maxOfOrNull { it.toDouble() })
            println(xs.maxOfOrNull { it.toFloat() })
            println(xs.maxOfOrNull { "x" })
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Iterable maxOfOrNull calls to resolve, got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "maxOfOrNull", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 4, "Expected four user maxOfOrNull calls, got \(calls)")

        let expected: [SelectorReturn] = [.generic, .double, .float, .generic]
        for (callID, want) in zip(calls, expected) {
            try Self.expectSelectorReturn(want, callID: callID, calleeName: "maxOfOrNull", sema: sema)
        }
    }

    @Test
    func iterableExtremaFamilyBindsOverloadBySelectorReturnType() throws {
        let source = """
        fun main() {
            val xs: Iterable<Int> = listOf(4, 5, 6)
            println(xs.minOfOrNull { it })
            println(xs.minOfOrNull { it.toDouble() })
            println(xs.maxOf { it })
            println(xs.maxOf { it.toDouble() })
            println(xs.minOf { it })
            println(xs.minOf { it.toFloat() })
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Iterable extrema calls to resolve, got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let expectations: [(String, SelectorReturn)] = [
            ("minOfOrNull", .generic), ("minOfOrNull", .double),
            ("maxOf", .generic), ("maxOf", .double),
            ("minOf", .generic), ("minOf", .float),
        ]
        for (memberName, want) in expectations {
            // Match calls by source order: each member is called twice, the
            // plain `{ it }` selector first.
            let calls = memberCallExprIDs(named: memberName, in: ast, interner: ctx.interner)
                .filter { isUserSourceExpr($0, in: ctx) }
            let callID = want == .generic ? calls.first : calls.dropFirst().first
            let resolvedCallID = try #require(
                callID,
                "\(memberName): expected a user call for selector \(want)"
            )
            try Self.expectSelectorReturn(want, callID: resolvedCallID, calleeName: memberName, sema: sema)
        }
    }

    @Test
    func iterableMaxOfOrNullResultTypeFollowsSelectorReturnType() throws {
        let source = """
        fun pick(xs: Iterable<Int>): Int? = xs.maxOfOrNull { it }
        fun pickD(xs: Iterable<Int>): Double? = xs.maxOfOrNull { it.toDouble() }
        fun pickS(xs: Iterable<Int>): String? = xs.maxOfOrNull { "x" }
        fun main() {
            val xs: Iterable<Int> = listOf(4, 5, 6)
            val i: Int? = xs.maxOfOrNull { it }
            val d: Double? = xs.maxOfOrNull { it.toDouble() }
            val f: Float? = xs.maxOfOrNull { it.toFloat() }
            println("$i $d $f")
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "selector-typed results must satisfy Int?/Double?/Float?/String? bindings; got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "maxOfOrNull", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 6, "Expected six user maxOfOrNull calls, got \(calls)")

        let expectedReturnTypes: [TypeID] = [
            sema.types.makeNullable(sema.types.intType),
            sema.types.makeNullable(sema.types.doubleType),
            sema.types.makeNullable(sema.types.stringType),
            sema.types.makeNullable(sema.types.intType),
            sema.types.makeNullable(sema.types.doubleType),
            sema.types.makeNullable(sema.types.floatType),
        ]
        for (callID, want) in zip(calls, expectedReturnTypes) {
            let bound = try #require(
                sema.bindings.exprType(for: callID),
                "maxOfOrNull call must carry a bound expression type"
            )
            #expect(
                bound == want,
                "maxOfOrNull result must be the selector's nullable return type; got \(sema.types.renderType(bound))"
            )
        }
    }

    /// A selector supplied as a function-typed value (not a lambda literal
    /// or callable reference) must still admit the HOF overloads — the
    /// fallback previously filtered every candidate out, left the call
    /// unbound, and emitted a dangling `maxOfOrNull` reference that failed
    /// at link time.
    @Test
    func iterableMaxOfOrNullBindsFunctionTypedSelectorArgument() throws {
        let source = """
        fun main() {
            val xs: Iterable<Int> = listOf(4, 5, 6)
            val intSelector = { x: Int -> x }
            val doubleSelector: (Int) -> Double = { x -> x.toDouble() }
            println(xs.maxOfOrNull(intSelector))
            println(xs.maxOfOrNull(doubleSelector))
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "function-typed selector arguments must resolve, got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "maxOfOrNull", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 2, "Expected two user maxOfOrNull calls, got \(calls)")

        let expected: [SelectorReturn] = [.generic, .double]
        for (callID, want) in zip(calls, expected) {
            try Self.expectSelectorReturn(want, callID: callID, calleeName: "maxOfOrNull", sema: sema)
        }
    }
}
#endif
