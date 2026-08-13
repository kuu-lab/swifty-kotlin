#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// BUG-046: explicit lambda parameter type annotations (`{ a: Int, b: Int -> ... }`)
/// must be preserved by the parser and honoured by type inference, including when
/// the expected type cannot determine the parameter types (raw `fun interface`
/// SAM constructors) or when there is no expected type at all.
@Suite
struct LambdaParamTypeAnnotationTests {

    private static let sources: [String] = [
        // 0: testRawSamConstructorUsesLambdaParamAnnotations
        """
        package sample0

        fun interface Cmp<T> { fun compare(a: T, b: T): Int }

        fun main() {
            val c = Cmp { a: Int, b: Int -> a - b }
            println(c.compare(3, 1))
        }
        """,
        // 1: testAnnotatedPlainLambdaRejectsMismatchedArgumentTypes
        """
        package sample1

        fun main() {
            val f = { a: Int, b: Int -> a - b }
            println(f("x", "y"))
        }
        """,
        // 2: testAnnotatedPlainLambdaAcceptsMatchingArgumentTypes
        """
        package sample2

        fun main() {
            val f = { a: Int, b: Int -> a - b }
            println(f(5, 2))
        }
        """,
        // 3: testAnnotatedLambdaWithExpectedFunctionTypeStillResolves
        """
        package sample3

        fun main() {
            val g: (String) -> Int = { s: String -> s.length }
            println(g("hello"))
        }
        """,
        // 4: testAnnotationContradictingExpectedFunctionTypeIsRejected
        """
        package sample4

        fun main() {
            val g: (String) -> Int = { s: Int -> s + 1 }
            println(g("hi"))
        }
        """,
        // 5: testAnnotationContradictingSamTypeArgumentIsRejected
        """
        package sample5

        fun interface Cmp<T> { fun compare(a: T, b: T): Int }

        fun main() {
            val c: Cmp<String> = Cmp { a: Int, b: Int -> a - b }
            println(c.compare("a", "b"))
        }
        """,
        // 6: testAnnotationContradictingHigherOrderParameterIsRejected
        """
        package sample6

        fun main() {
            println(listOf(1, 2, 3).map { s: String -> s.length })
        }
        """,
        // 7: testAnnotationNarrowingExpectedParameterTypeIsRejected
        """
        package sample7

        fun main() {
            val f: (CharSequence) -> Int = { s: String -> s.length }
            println(f("ab"))
        }
        """,
        // 8: testAnnotationDroppingExpectedNullabilityIsRejected
        """
        package sample8

        fun main() {
            val f: (String?) -> Int = { s: String -> s.length }
            println(f(null))
        }
        """,
        // 9: testAnnotationNarrowingDeclaredAnyIsRejected
        """
        package sample9

        fun main() {
            val f: (Any) -> Int = { s: String -> s.length }
            println(f(42))
        }
        """,
        // 10: testAnnotationNarrowingDeclaredAnyOfTopLevelPropertyIsRejected
        """
        package sample10

        val f: (Any) -> Int = { s: String -> s.length }

        fun main() {
            println(f(42))
        }
        """,
        // 11: testAnnotationNarrowingDeclaredAnyFunctionParameterIsRejected
        """
        package sample11

        fun applyAny(f: (Any) -> Int): Int = f(42)

        fun main() {
            println(applyAny { s: String -> s.length })
        }
        """,
        // 12: testAnnotationMatchingDeclaredAnyIsAccepted
        """
        package sample12

        fun applyAny(f: (Any) -> String): String = f(42)

        fun main() {
            val f: (Any) -> String = { v: Any -> v.toString() }
            println(f(7))
            println(applyAny { v: Any -> v.toString() })
        }
        """,
        // 13: testAnnotationIsKeptWhereInferenceFallsBackToAny
        """
        package sample13

        fun main() {
            val grouping: Grouping<Int, Int> = listOf(3, 1, 4, 2, 5).groupingBy { value: Int -> value % 2 }
            println(grouping.fold(
                initialValueSelector = { key: Int, element: Int -> key * 100 + element },
                operation = { key: Int, accumulator: Int, element: Int -> accumulator + key + element }
            ))
        }
        """,
        // 14: testAnnotationWideningExpectedParameterTypeIsAccepted
        """
        package sample14

        fun main() {
            val f: (String) -> Int = { s: Any -> s.toString().length }
            println(f("hi"))
        }
        """,
        // 15: testPartiallyAnnotatedLambdaKeepsExpectedTypesForUnannotatedParams
        """
        package sample15

        fun main() {
            val q: (Int, String) -> Int = { a: Int, b -> a + b.length }
            println(q(7, "zz"))
        }
        """,
        // 16: testParserRecordsLambdaParamTypeAnnotations
        """
        package sample16

        fun main() {
            val f = { a: Int, b: String -> b.length + a }
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

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    @Test
    func testRawSamConstructorUsesLambdaParamAnnotations() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Raw SAM constructor should adopt the annotated Int parameters, got: \\(errors)"
        )
    }

    @Test
    func testAnnotatedPlainLambdaRejectsMismatchedArgumentTypes() throws {
        let (ctx, paths) = try shared()
        let sampleDiagnostics = diagnosticsForPath(paths[1], in: ctx)
        #expect(
            sampleDiagnostics.contains { $0.severity == .error },
            "Calling an (Int, Int) -> Int lambda with String arguments must be an error"
        )
    }

    @Test
    func testAnnotatedPlainLambdaAcceptsMatchingArgumentTypes() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Matching call on an annotated lambda should type-check, got: \\(errors)"
        )
    }

    @Test
    func testAnnotatedLambdaWithExpectedFunctionTypeStillResolves() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[3], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Annotation matching the expected function type should type-check, got: \\(errors)"
        )
    }

    @Test
    func testAnnotationContradictingExpectedFunctionTypeIsRejected() throws {
        let (ctx, paths) = try shared()
        let mismatches = diagnosticsForPath(paths[4], in: ctx).filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(
            mismatches.count == 1,
            "Annotation contradicting the expected function type must be reported, got: \\(mismatches)"
        )
    }

    @Test
    func testAnnotationContradictingSamTypeArgumentIsRejected() throws {
        let (ctx, paths) = try shared()
        let mismatches = diagnosticsForPath(paths[5], in: ctx).filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(
            mismatches.count == 2,
            "Both annotations contradicting Cmp<String> must be reported, got: \\(mismatches)"
        )
    }

    @Test
    func testAnnotationContradictingHigherOrderParameterIsRejected() throws {
        let (ctx, paths) = try shared()
        let sampleDiagnostics = diagnosticsForPath(paths[6], in: ctx)
        #expect(
            sampleDiagnostics.contains { $0.severity == .error },
            "`map { s: String -> ... }` on a List<Int> must not type-check"
        )
    }

    @Test
    func testAnnotationNarrowingExpectedParameterTypeIsRejected() throws {
        let (ctx, paths) = try shared()
        let mismatches = diagnosticsForPath(paths[7], in: ctx).filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(
            mismatches.count == 1,
            "Narrowing the expected parameter type must be reported, got: \\(mismatches)"
        )
    }

    @Test
    func testAnnotationDroppingExpectedNullabilityIsRejected() throws {
        let (ctx, paths) = try shared()
        let mismatches = diagnosticsForPath(paths[8], in: ctx).filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(
            mismatches.count == 1,
            "A non-null annotation for a nullable parameter must be reported, got: \\(mismatches)"
        )
    }

    @Test
    func testAnnotationNarrowingDeclaredAnyIsRejected() throws {
        let (ctx, paths) = try shared()
        let mismatches = diagnosticsForPath(paths[9], in: ctx).filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(
            mismatches.count == 1,
            "Narrowing a declared `Any` parameter must be reported, got: \\(mismatches)"
        )
    }

    @Test
    func testAnnotationNarrowingDeclaredAnyOfTopLevelPropertyIsRejected() throws {
        let (ctx, paths) = try shared()
        let mismatches = diagnosticsForPath(paths[10], in: ctx).filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(
            mismatches.count == 1,
            "Narrowing a declared `Any` property parameter must be reported, got: \\(mismatches)"
        )
    }

    @Test
    func testAnnotationNarrowingDeclaredAnyFunctionParameterIsRejected() throws {
        let (ctx, paths) = try shared()
        let mismatches = diagnosticsForPath(paths[11], in: ctx).filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(
            mismatches.count == 1,
            "Narrowing a declared `Any` function parameter must be reported, got: \\(mismatches)"
        )
    }

    @Test
    func testAnnotationMatchingDeclaredAnyIsAccepted() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[12], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "An `Any` annotation for a declared `Any` parameter is legal, got: \\(errors)"
        )
    }

    @Test
    func testAnnotationIsKeptWhereInferenceFallsBackToAny() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[13], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "An unsolved accumulator type falls back to Any and must not reject the annotation, got: \\(errors)"
        )
    }

    @Test
    func testAnnotationWideningExpectedParameterTypeIsAccepted() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[14], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Widening annotations are legal in Kotlin, got: \\(errors)"
        )
    }

    @Test
    func testPartiallyAnnotatedLambdaKeepsExpectedTypesForUnannotatedParams() throws {
        let (ctx, paths) = try shared()
        let errors = diagnosticsForPath(paths[15], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Partially annotated lambda should type-check, got: \\(errors)"
        )
    }

    @Test
    func testParserRecordsLambdaParamTypeAnnotations() throws {
        let (ctx, paths) = try shared()
        let samplePath = paths[16]
        let arena = try #require(ctx.ast).arena
        let lambdaIDs = arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard let expr = arena.expr(id),
                  case .lambdaLiteral(_, _, _, let range) = expr,
                  ctx.sourceManager.path(of: range.start.file) == samplePath
            else { return nil }
            return id
        }
        let annotated = lambdaIDs.compactMap { arena.lambdaParamTypeRefs(for: $0) }
        #expect(annotated.count == 1, "Exactly one lambda should carry parameter annotations")
        #expect(annotated.first?.count == 2, "Both annotated parameters should be recorded")
        #expect(
            annotated.first?.allSatisfy { $0 != nil } == true,
            "Both annotations should resolve to a type ref"
        )
    }
}
#endif
