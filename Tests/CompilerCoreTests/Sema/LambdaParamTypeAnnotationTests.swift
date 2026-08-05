#if canImport(Testing)
@testable import CompilerCore
import Testing

/// BUG-046: explicit lambda parameter type annotations (`{ a: Int, b: Int -> ... }`)
/// must be preserved by the parser and honoured by type inference, including when
/// the expected type cannot determine the parameter types (raw `fun interface`
/// SAM constructors) or when there is no expected type at all.
@Suite
struct LambdaParamTypeAnnotationTests {

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testRawSamConstructorUsesLambdaParamAnnotations
            """
            package sample0

                    fun interface Cmp<T> { fun compare(a: T, b: T): Int }

                    fun main() {
                        val c = Cmp { a: Int, b: Int -> a - b }
                        println(c.compare(3, 1))
                    }

            """,
            // testAnnotatedPlainLambdaRejectsMismatchedArgumentTypes
            """
            package sample1

                    fun main() {
                        val f = { a: Int, b: Int -> a - b }
                        println(f("x", "y"))
                    }

            """,
            // testAnnotatedPlainLambdaAcceptsMatchingArgumentTypes
            """
            package sample2

                    fun main() {
                        val f = { a: Int, b: Int -> a - b }
                        println(f(5, 2))
                    }

            """,
            // testAnnotatedLambdaWithExpectedFunctionTypeStillResolves
            """
            package sample3

                    fun main() {
                        val g: (String) -> Int = { s: String -> s.length }
                        println(g("hello"))
                    }

            """,
            // testAnnotationContradictingExpectedFunctionTypeIsRejected
            """
            package sample4

                    fun main() {
                        val g: (String) -> Int = { s: Int -> s + 1 }
                        println(g("hi"))
                    }

            """,
            // testAnnotationContradictingSamTypeArgumentIsRejected
            """
            package sample5

                    fun interface Cmp<T> { fun compare(a: T, b: T): Int }

                    fun main() {
                        val c: Cmp<String> = Cmp { a: Int, b: Int -> a - b }
                        println(c.compare("a", "b"))
                    }

            """,
            // testAnnotationContradictingHigherOrderParameterIsRejected
            """
            package sample6

                    fun main() {
                        println(listOf(1, 2, 3).map { s: String -> s.length })
                    }

            """,
            // testAnnotationNarrowingExpectedParameterTypeIsRejected
            """
            package sample7

                    fun main() {
                        val f: (CharSequence) -> Int = { s: String -> s.length }
                        println(f("ab"))
                    }

            """,
            // testAnnotationDroppingExpectedNullabilityIsRejected
            """
            package sample8

                    fun main() {
                        val f: (String?) -> Int = { s: String -> s.length }
                        println(f(null))
                    }

            """,
            // testAnnotationIsKeptWhereInferenceFallsBackToAny
            """
            package sample9

                    fun main() {
                        val grouping: Grouping<Int, Int> = listOf(3, 1, 4, 2, 5).groupingBy { value: Int -> value % 2 }
                        println(grouping.fold(
                            initialValueSelector = { key: Int, element: Int -> key * 100 + element },
                            operation = { key: Int, accumulator: Int, element: Int -> accumulator + key + element }
                        ))
                    }

            """,
            // testAnnotationWideningExpectedParameterTypeIsAccepted
            """
            package sample10

                    fun main() {
                        val f: (String) -> Int = { s: Any -> s.toString().length }
                        println(f("hi"))
                    }

            """,
            // testPartiallyAnnotatedLambdaKeepsExpectedTypesForUnannotatedParams
            """
            package sample11

                    fun main() {
                        val q: (Int, String) -> Int = { a: Int, b -> a + b.length }
                        println(q(7, "zz"))
                    }

            """,
            // testParserRecordsLambdaParamTypeAnnotations
            """
            package sample12

                    fun main() {
                        val f = { a: Int, b: String -> b.length + a }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testRawSamConstructorUsesLambdaParamAnnotations ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Raw SAM constructor should adopt the annotated Int parameters, got: \\(errors)"
                )

            }

            // === testAnnotatedPlainLambdaRejectsMismatchedArgumentTypes ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                // Without the annotations the lambda parameters degraded to `Any`, so the
                // mismatched call was accepted by Sema and only crashed in codegen.
                #expect(
                    sample1Diagnostics.contains { $0.severity == .error },
                    "Calling an (Int, Int) -> Int lambda with String arguments must be an error"
                )

            }

            // === testAnnotatedPlainLambdaAcceptsMatchingArgumentTypes ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(errors.isEmpty, "Matching call on an annotated lambda should type-check, got: \\(errors)")

            }

            // === testAnnotatedLambdaWithExpectedFunctionTypeStillResolves ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let errors = sample3Diagnostics.filter { $0.severity == .error }
                #expect(errors.isEmpty, "Annotation matching the expected function type should type-check, got: \\(errors)")

            }

            // === testAnnotationContradictingExpectedFunctionTypeIsRejected ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let mismatches = sample4Diagnostics.filter { $0.code == "KSWIFTK-SEMA-0025" }
                #expect(
                    mismatches.count == 1,
                    "Annotation contradicting the expected function type must be reported, got: \\(sample4Diagnostics)"
                )

            }

            // === testAnnotationContradictingSamTypeArgumentIsRejected ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let mismatches = sample5Diagnostics.filter { $0.code == "KSWIFTK-SEMA-0025" }
                #expect(
                    mismatches.count == 2,
                    "Both annotations contradicting Cmp<String> must be reported, got: \\(sample5Diagnostics)"
                )

            }

            // === testAnnotationContradictingHigherOrderParameterIsRejected ===

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                #expect(
                    sample6Diagnostics.contains { $0.severity == .error },
                    "`map { s: String -> ... }` on a List<Int> must not type-check"
                )

            }

            // === testAnnotationNarrowingExpectedParameterTypeIsRejected ===

            do {

                let sample7Path = paths[7]

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let mismatches = sample7Diagnostics.filter { $0.code == "KSWIFTK-SEMA-0025" }
                #expect(
                    mismatches.count == 1,
                    "Narrowing the expected parameter type must be reported, got: \\(sample7Diagnostics)"
                )

            }

            // === testAnnotationDroppingExpectedNullabilityIsRejected ===

            do {

                let sample8Path = paths[8]

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let mismatches = sample8Diagnostics.filter { $0.code == "KSWIFTK-SEMA-0025" }
                #expect(
                    mismatches.count == 1,
                    "A non-null annotation for a nullable parameter must be reported, got: \\(sample8Diagnostics)"
                )

            }

            // === testAnnotationIsKeptWhereInferenceFallsBackToAny ===

            do {

                let sample9Path = paths[9]

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let errors = sample9Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "An unsolved accumulator type falls back to Any and must not reject the annotation, got: \\(errors)"
                )

            }

            // === testAnnotationWideningExpectedParameterTypeIsAccepted ===

            do {

                let sample10Path = paths[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let errors = sample10Diagnostics.filter { $0.severity == .error }
                #expect(errors.isEmpty, "Widening annotations are legal in Kotlin, got: \\(errors)")

            }

            // === testPartiallyAnnotatedLambdaKeepsExpectedTypesForUnannotatedParams ===

            do {

                let sample11Path = paths[11]

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let errors = sample11Diagnostics.filter { $0.severity == .error }
                #expect(errors.isEmpty, "Partially annotated lambda should type-check, got: \\(errors)")

            }

            // === testParserRecordsLambdaParamTypeAnnotations ===

            do {

                let sample12Path = paths[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let arena = ast.arena
                let lambdaIDs = arena.exprs.indices.compactMap { index -> ExprID? in
                    let id = ExprID(rawValue: Int32(index))
                    guard case .lambdaLiteral(_, _, _, let range) = arena.expr(id),
                          ctx.sourceManager.path(of: range.start.file) == sample12Path
                    else { return nil }
                    return id
                }
                let annotated = lambdaIDs.compactMap { arena.lambdaParamTypeRefs(for: $0) }
                #expect(annotated.count == 1, "Exactly one lambda should carry parameter annotations")
                #expect(annotated.first?.count == 2, "Both annotated parameters should be recorded")
                #expect(annotated.first?.allSatisfy { $0 != nil } == true, "Both annotations should resolve to a type ref")

            }

        }
    }

}

#endif
