#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-2990: a lambda literal whose declared parameter count does not match the
/// expected function type must be rejected — `(Int, Int) -> Unit = { }` cannot
/// use an implicit `it`, and explicit parameters must match the arity exactly.
@Suite
struct LambdaArityMatchTests {

    private static let rejectSources: [String] = [
        // 0: implicit `it` against a two-parameter expected type
        """
        package reject0

        val f: (Int, Int) -> Unit = { }
        """,
        // 1: one declared parameter against a two-parameter expected type
        """
        package reject1

        val g: (Int, Int) -> Unit = { a -> println(a) }
        """,
        // 2: two declared parameters against a one-parameter expected type
        """
        package reject2

        val h: (Int) -> Unit = { a, b -> println(a) }
        """,
        // 3: one declared parameter against a zero-parameter expected type
        """
        package reject3

        val i: () -> Unit = { a -> println(a) }
        """,
        // 4: SAM conversion with a two-parameter abstract method
        """
        package reject4

        fun interface Cmp { fun compare(a: Int, b: Int): Int }

        val c = Cmp { }
        """,
        // 5: suspend function type still enforces arity
        """
        package reject5

        val s: suspend (Int, Int) -> Unit = { }
        """,
        // 6: extension function type with two value parameters
        """
        package reject6

        val e: Int.(String, String) -> Unit = { }
        """,
        // 7: trailing lambda against a two-parameter HOF argument
        """
        package reject7

        fun consume(f: (Int, Int) -> Unit) = f(1, 2)

        fun main() {
            consume { }
        }
        """,
        // 8: nullable function type keeps the arity contract
        """
        package reject8

        val n: ((Int, Int) -> Unit)? = { }
        """,
    ]

    private static let acceptSources: [String] = [
        // 0: implicit `it` for a single-parameter expected type
        """
        package accept0

        val f: (Int) -> Unit = { }
        """,
        // 1: zero-parameter lambda against a zero-parameter expected type,
        //    plus an uncontextualized lambda with no expected type at all
        """
        package accept1

        val f: () -> Unit = { }
        val g = { }
        """,
        // 2: matching two-parameter lambda
        """
        package accept2

        val f: (Int, Int) -> Unit = { a, b -> println(a + b) }
        """,
        // 3: extension receiver does not count toward `it` arity
        """
        package accept3

        val e: Int.(String) -> Unit = { println(it.length + this) }
        """,
        // 4: SAM conversion with matching arity
        """
        package accept4

        fun interface Cmp { fun compare(a: Int, b: Int): Int }

        fun main() {
            val c = Cmp { a, b -> a - b }
            println(c.compare(3, 1))
        }
        """,
        // 5: directly-invoked annotated lambda — the synthetic `() -> Any`
        //    expected type carries no arity contract (`{ x: Int -> }(4)` is
        //    accepted by kotlinc)
        """
        package accept5

        fun main() {
            { x: Int -> println(x) }(4)
        }
        """,
        // 6: matching trailing lambda arity
        """
        package accept6

        fun consume(f: (Int, Int) -> Unit) = f(1, 2)

        fun main() {
            consume { a, b -> println(a + b) }
        }
        """,
        // 7: destructured parameter still counts as one declared parameter
        """
        package accept7

        fun main() {
            println(listOf(2 to 3).fold(0) { acc, (first, second) -> acc + first * second })
        }
        """,
    ]

    private static nonisolated(unsafe) var _rejectShared: (ctx: CompilationContext, paths: [String])?
    private static nonisolated(unsafe) var _acceptShared: (ctx: CompilationContext, paths: [String])?

    private func rejectShared() throws -> (ctx: CompilationContext, paths: [String]) {
        if let cached = Self._rejectShared { return cached }
        var result: (ctx: CompilationContext, paths: [String])?
        try withTemporaryFiles(contents: Self.rejectSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let pair = try #require(result)
        Self._rejectShared = pair
        return pair
    }

    private func acceptShared() throws -> (ctx: CompilationContext, paths: [String]) {
        if let cached = Self._acceptShared { return cached }
        var result: (ctx: CompilationContext, paths: [String])?
        try withTemporaryFiles(contents: Self.acceptSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let pair = try #require(result)
        Self._acceptShared = pair
        return pair
    }

    private func expectArityMismatch(index: Int, sourceLocation: String) async throws {
        let (ctx, paths) = try rejectShared()
        let mismatches = diagnosticsForPath(paths[index], in: ctx).filter {
            $0.code == "KSWIFTK-SEMA-0433"
        }
        #expect(
            !mismatches.isEmpty,
            "\(sourceLocation): expected KSWIFTK-SEMA-0433, got: \(diagnosticsForPath(paths[index], in: ctx))"
        )
    }

    @Test
    func implicitItAgainstTwoParametersIsRejected() async throws {
        try await expectArityMismatch(index: 0, sourceLocation: "val f: (Int, Int) -> Unit = { }")
    }

    @Test
    func oneDeclaredParameterAgainstTwoExpectedIsRejected() async throws {
        try await expectArityMismatch(index: 1, sourceLocation: "{ a -> } vs (Int, Int) -> Unit")
    }

    @Test
    func twoDeclaredParametersAgainstOneExpectedIsRejected() async throws {
        try await expectArityMismatch(index: 2, sourceLocation: "{ a, b -> } vs (Int) -> Unit")
    }

    @Test
    func oneDeclaredParameterAgainstZeroExpectedIsRejected() async throws {
        try await expectArityMismatch(index: 3, sourceLocation: "{ a -> } vs () -> Unit")
    }

    @Test
    func samLambdaWithMissingParametersIsRejected() async throws {
        try await expectArityMismatch(index: 4, sourceLocation: "Cmp { }")
    }

    @Test
    func suspendFunctionTypeArityMismatchIsRejected() async throws {
        try await expectArityMismatch(index: 5, sourceLocation: "suspend (Int, Int) -> Unit = { }")
    }

    @Test
    func extensionFunctionTypeArityMismatchIsRejected() async throws {
        try await expectArityMismatch(index: 6, sourceLocation: "Int.(String, String) -> Unit = { }")
    }

    @Test
    func trailingLambdaArityMismatchIsRejected() async throws {
        let (ctx, paths) = try rejectShared()
        let diagnostics = diagnosticsForPath(paths[7], in: ctx)
        #expect(
            diagnostics.contains { $0.severity == .error },
            "`consume { }` with a (Int, Int) -> Unit parameter must be an error, got: \(diagnostics)"
        )
    }

    @Test
    func nullableFunctionTypeArityMismatchIsRejected() async throws {
        try await expectArityMismatch(index: 8, sourceLocation: "((Int, Int) -> Unit)? = { }")
    }

    private func expectClean(index: Int, sourceLocation: String) async throws {
        let (ctx, paths) = try acceptShared()
        let errors = diagnosticsForPath(paths[index], in: ctx).filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(sourceLocation): \(errors)")
    }

    @Test
    func implicitItForSingleParameterIsAccepted() async throws {
        try await expectClean(index: 0, sourceLocation: "val f: (Int) -> Unit = { }")
    }

    @Test
    func zeroParameterAndUncontextualizedLambdasAreAccepted() async throws {
        try await expectClean(index: 1, sourceLocation: "val f: () -> Unit = { }")
    }

    @Test
    func matchingTwoParameterLambdaIsAccepted() async throws {
        try await expectClean(index: 2, sourceLocation: "{ a, b -> } vs (Int, Int) -> Unit")
    }

    @Test
    func extensionReceiverKeepsImplicitIt() async throws {
        try await expectClean(index: 3, sourceLocation: "Int.(String) -> Unit = { }")
    }

    @Test
    func samLambdaWithMatchingArityIsAccepted() async throws {
        try await expectClean(index: 4, sourceLocation: "Cmp { a, b -> }")
    }

    @Test
    func directlyInvokedAnnotatedLambdaIsAccepted() async throws {
        try await expectClean(index: 5, sourceLocation: "{ x: Int -> }(4)")
    }

    @Test
    func matchingTrailingLambdaIsAccepted() async throws {
        try await expectClean(index: 6, sourceLocation: "consume { a, b -> }")
    }

    @Test
    func destructuredParameterCountsAsOne() async throws {
        try await expectClean(index: 7, sourceLocation: "fold { acc, (a, b) -> }")
    }
}
#endif
