#if canImport(Testing)
@testable import CompilerCore
import Testing

/// BUG-046: explicit lambda parameter type annotations (`{ a: Int, b: Int -> ... }`)
/// must be preserved by the parser and honoured by type inference, including when
/// the expected type cannot determine the parameter types (raw `fun interface`
/// SAM constructors) or when there is no expected type at all.
@Suite
struct LambdaParamTypeAnnotationTests {

    @Test func testRawSamConstructorUsesLambdaParamAnnotations() throws {
        let source = """
        fun interface Cmp<T> { fun compare(a: T, b: T): Int }

        fun main() {
            val c = Cmp { a: Int, b: Int -> a - b }
            println(c.compare(3, 1))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Raw SAM constructor should adopt the annotated Int parameters, got: \\(errors)"
        )
    }

    @Test func testAnnotatedPlainLambdaRejectsMismatchedArgumentTypes() throws {
        // Without the annotations the lambda parameters degraded to `Any`, so the
        // mismatched call was accepted by Sema and only crashed in codegen.
        let source = """
        fun main() {
            val f = { a: Int, b: Int -> a - b }
            println(f("x", "y"))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Calling an (Int, Int) -> Int lambda with String arguments must be an error"
        )
    }

    @Test func testAnnotatedPlainLambdaAcceptsMatchingArgumentTypes() throws {
        let source = """
        fun main() {
            val f = { a: Int, b: Int -> a - b }
            println(f(5, 2))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Matching call on an annotated lambda should type-check, got: \\(errors)")
    }

    @Test func testAnnotatedLambdaWithExpectedFunctionTypeStillResolves() throws {
        let source = """
        fun main() {
            val g: (String) -> Int = { s: String -> s.length }
            println(g("hello"))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Annotation matching the expected function type should type-check, got: \\(errors)")
    }

    @Test func testParserRecordsLambdaParamTypeAnnotations() throws {
        let source = """
        fun main() {
            val f = { a: Int, b: String -> b.length + a }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let arena = try #require(ctx.ast).arena
        let lambdaIDs = arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case .lambdaLiteral = arena.expr(id) else { return nil }
            return id
        }
        let annotated = lambdaIDs.compactMap { arena.lambdaParamTypeRefs(for: $0) }
        #expect(annotated.count == 1, "Exactly one lambda should carry parameter annotations")
        #expect(annotated.first?.count == 2, "Both annotated parameters should be recorded")
        #expect(annotated.first?.allSatisfy { $0 != nil } == true, "Both annotations should resolve to a type ref")
    }
}
#endif
