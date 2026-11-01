#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

// KUU-3923: kotlinc reports every non-exhaustive `when` error as
// NO_ELSE_IN_WHEN — sealed subjects name the missing branches
// (KSWIFTK-SEMA-0071) while enum/Boolean/subject-less subjects take the
// generic form (KSWIFTK-SEMA-0004). `@Suppress("NO_ELSE_IN_WHEN")` must
// silence both codes. NON_EXHAUSTIVE_WHEN is a distinct warning-level
// upstream diagnostic: kotlinc does not let it suppress the error, so it
// deliberately has no mapping here either.
@Suite
struct WhenExhaustivenessSuppressionTests {
    private func context(for source: String) throws -> CompilationContext {
        try semaContext(for: [source])
    }

    @Test func noElseInWhenSuppressesSealedWhenOnFunction() throws {
        // KUU-3923 MRE shape: sealed subject, statement position.
        let ctx = try context(for: """
            sealed interface A
            interface B : A
            interface C : A

            @Suppress("NO_ELSE_IN_WHEN")
            fun f(x: A) {
                when (x) {
                    is B -> println("b")
                }
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map { $0.code + ": " + $0.message })")
    }

    @Test func noElseInWhenSuppressesSealedWhenExpression() throws {
        let ctx = try context(for: """
            sealed interface A
            interface B : A
            interface C : A

            @Suppress("NO_ELSE_IN_WHEN")
            fun f(x: A): Int = when (x) {
                is B -> 1
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func noElseInWhenSuppressesEnumWhen() throws {
        // Non-sealed closed-domain subjects report the generic
        // KSWIFTK-SEMA-0004; upstream still calls it NO_ELSE_IN_WHEN.
        let ctx = try context(for: """
            enum class E { X, Y }

            @Suppress("NO_ELSE_IN_WHEN")
            fun f(e: E): Int = when (e) {
                E.X -> 1
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func noElseInWhenSuppressesSubjectlessWhen() throws {
        let ctx = try context(for: """
            @Suppress("NO_ELSE_IN_WHEN")
            fun f(x: Int): Int = when {
                x > 0 -> 1
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func fileLevelNoElseInWhenSuppressesSealedWhen() throws {
        let ctx = try context(for: """
            @file:Suppress("NO_ELSE_IN_WHEN")

            sealed interface A
            interface B : A
            interface C : A

            fun f(x: A) {
                when (x) {
                    is B -> println("b")
                }
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func suppressionIsScopedToAnnotatedDeclaration() throws {
        // Only `f` is annotated: `g`'s identical non-exhaustive `when` must
        // still be diagnosed.
        let ctx = try context(for: """
            sealed interface A
            interface B : A
            interface C : A

            @Suppress("NO_ELSE_IN_WHEN")
            fun f(x: A) {
                when (x) {
                    is B -> println("b")
                }
            }

            fun g(x: A) {
                when (x) {
                    is B -> println("b")
                }
            }
            """)
        let matching = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0071" }
        #expect(matching.count == 1, "Expected exactly one SEMA-0071 (from `g`), got: \(matching)")
    }

    @Test func nonExhaustiveSealedWhenWithoutSuppressionStillErrors() throws {
        let ctx = try context(for: """
            sealed interface A
            interface B : A
            interface C : A

            fun f(x: A) {
                when (x) {
                    is B -> println("b")
                }
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func conditionTypeMismatchSuppressesSubjectlessWhenCondition() throws {
        // kotlinc reports a non-Boolean subject-less `when` condition as
        // CONDITION_TYPE_MISMATCH; ours is KSWIFTK-SEMA-0032.
        let ctx = try context(for: """
            @Suppress("CONDITION_TYPE_MISMATCH")
            fun f(x: Int) {
                when {
                    "s" -> println("s")
                    else -> println("e")
                }
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0032", in: ctx)
    }

    @Test func subjectlessWhenConditionWithoutSuppressionStillErrors() throws {
        let ctx = try context(for: """
            fun f(x: Int) {
                when {
                    "s" -> println("s")
                    else -> println("e")
                }
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0032", in: ctx)
    }

    @Test func nonExhaustiveWhenNameDoesNotSuppress() throws {
        // kotlinc: NON_EXHAUSTIVE_WHEN is a warning-level name and does not
        // silence the NO_ELSE_IN_WHEN error.
        let ctx = try context(for: """
            sealed interface A
            interface B : A
            interface C : A

            @Suppress("NON_EXHAUSTIVE_WHEN")
            fun f(x: A) {
                when (x) {
                    is B -> println("b")
                }
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }
}
#endif
