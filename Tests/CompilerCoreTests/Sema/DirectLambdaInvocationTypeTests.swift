#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KUU-1380 (sema): a directly-invoked lambda literal gets a synthesized
/// `() -> Any`-shaped contextual type when no caller expected type exists.
/// The lambda must still return its own concrete body type — adopting `Any`
/// verbatim made `true && { 1; true }()` fail `&&`'s Boolean constraint
/// (`KSWIFTK-TYPE-0001`) and mistyped `val v = { 42 }()` as `Any`.
/// Parameters of a directly-invoked literal are not inferred from the call's
/// arguments (`{ it }(4)` must stay rejected, matching kotlinc).
@Suite
struct DirectLambdaInvocationTypeTests {

    private static let sources: [String] = [
        // 0: testBooleanOperatorsAcceptDirectlyInvokedLambda
        """
        package sample0

        fun main() {
            println(true && { 1; true }())
            println(false || { 1; false }())
        }
        """,
        // 1: testDirectlyInvokedLambdaInCallArgument
        """
        package sample1

        fun main() {
            println({ 42 }())
            println({ 5 }() + { 6 }())
        }
        """,
        // 2: testDirectlyInvokedLambdaInfersBodyReturnType
        """
        package sample2

        fun main() {
            val v = { 42 }()
            val i: Int = v
            println(v + 1)
        }
        """,
        // 3: testAnnotatedParameterLambdaInvokedWithArgument
        """
        package sample3

        fun main() {
            println({ x: Int -> x * 3 }(4))
        }
        """,
        // 4: testImplicitItParameterRejectedWithoutExpectedType
        """
        package sample4

        fun main() {
            println({ it * 3 }(4))
        }
        """,
        // 5: testDirectlyInvokedLambdaFeedsExpectedReturnType
        """
        package sample5

        fun takesInt(x: Int) { println(x) }

        fun main() {
            takesInt({ 9 }())
            val v: Int = { 8 }()
            println(v)
        }
        """,
    ]

    private static nonisolated(unsafe) var _shared: (ctx: CompilationContext, paths: [String])?

    private func shared() throws -> (ctx: CompilationContext, paths: [String]) {
        if let cached = Self._shared { return cached }
        var result: (ctx: CompilationContext, paths: [String])?
        try withTemporaryFiles(contents: Self.sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let pair = try #require(result)
        Self._shared = pair
        return pair
    }

    @Test
    func testBooleanOperatorsAcceptDirectlyInvokedLambda() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Directly-invoked lambda should satisfy the && / || Boolean constraint, got: \(errors)"
        )
    }

    @Test
    func testDirectlyInvokedLambdaInCallArgument() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Directly-invoked lambda call arguments should type-check, got: \(errors)"
        )
    }

    @Test
    func testDirectlyInvokedLambdaInfersBodyReturnType() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "The call result must take the lambda body's type (Int, not Any), got: \(errors)"
        )
    }

    @Test
    func testAnnotatedParameterLambdaInvokedWithArgument() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[3], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "An explicitly annotated parameter should accept the call argument, got: \(errors)"
        )
    }

    @Test
    func testImplicitItParameterRejectedWithoutExpectedType() throws {
        let (ctx, paths) = try shared()
        let sampleDiagnostics = diagnosticsForPath(paths[4], in: ctx)
        #expect(
            sampleDiagnostics.contains { $0.severity == .error },
            "kotlinc rejects `{ it }(4)` — 'it' cannot be inferred without a parameter list"
        )
    }

    @Test
    func testDirectlyInvokedLambdaFeedsExpectedReturnType() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[5], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "A caller expected return type should flow into the invoked lambda, got: \(errors)"
        )
    }
}
#endif
