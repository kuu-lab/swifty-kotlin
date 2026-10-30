#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

// KUU-3207: kotlinc reports an impossible `is` check as
// IMPOSSIBLE_IS_CHECK_ERROR when the subject's declared type is incompatible
// with the target, and as IMPOSSIBLE_IS_CHECK_WARNING when it is impossible
// only under a smart-cast (narrowed) type. Both names must suppress
// KSWIFTK-SEMA-0415 at the matching severity; the K1 name INCOMPATIBLE_TYPES
// deliberately does not suppress it, matching kotlinc.
@Suite
struct ImpossibleIsCheckSuppressionTests {
    private func context(for source: String) throws -> CompilationContext {
        try semaContext(for: [source])
    }

    @Test func impossibleIsCheckSuppressedByKotlincErrorName() throws {
        // JetBrains testData casts/kt59022.kt shape.
        let ctx = try context(for: """
            @file:Suppress("INCOMPATIBLE_TYPES", "IMPOSSIBLE_IS_CHECK_ERROR", "UNCHECKED_CAST")
            fun <T> unchecked(x: Any?) = x as T
            fun box() = unchecked<String>(null) is IntArray
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0415", in: ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map { $0.code + ": " + $0.message })")
    }

    @Test func impossibleIsCheckSuppressedOnDeclaration() throws {
        let ctx = try context(for: """
            class Box
            @Suppress("IMPOSSIBLE_IS_CHECK_ERROR")
            fun check(s: String) = s is Box
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0415", in: ctx)
    }

    @Test func impossibleIsCheckErrorWithoutSuppression() throws {
        let ctx = try context(for: """
            class Box
            fun check(s: String) = s is Box
            """)
        let matching = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0415" }
        #expect(matching.count == 1, "Expected one SEMA-0415, got: \(matching)")
        #expect(matching.first?.severity == .error, "Declared-type incompatibility must stay an error: \(matching)")
    }

    @Test func incompatibleTypesNameDoesNotSuppressImpossibleIsCheck() throws {
        // kotlinc keeps INCOMPATIBLE_TYPES and IMPOSSIBLE_IS_CHECK_ERROR as
        // separate diagnostics: suppressing the K1 name alone does not hide
        // the impossible-check error.
        let ctx = try context(for: """
            @file:Suppress("INCOMPATIBLE_TYPES")
            class Box
            fun check(s: String) = s is Box
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0415", in: ctx)
    }

    @Test func impossibleIsCheckOnlyUnderNarrowedTypeIsWarning() throws {
        // `x is Int` is impossible only because `x` is smart-cast to String;
        // the declared `Any` accepts the check, so kotlinc degrades it to
        // IMPOSSIBLE_IS_CHECK_WARNING instead of the hard error.
        let ctx = try context(for: """
            fun check(x: Any) {
                if (x is String) {
                    val a = x is Int
                }
            }
            """)
        let matching = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0415" }
        #expect(matching.count == 1, "Expected one SEMA-0415, got: \(matching)")
        #expect(matching.first?.severity == .warning, "Smart-cast-only incompatibility must be a warning: \(matching)")
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map { $0.code + ": " + $0.message })")
    }

    @Test func warningNameSuppressesWarningButNotError() throws {
        let ctx = try context(for: """
            @file:Suppress("IMPOSSIBLE_IS_CHECK_WARNING")
            fun check(x: Any) {
                if (x is String) {
                    val a = x is Int
                }
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0415", in: ctx)

        // The warning-scoped name must not hide the error-severity variant.
        let errorCtx = try context(for: """
            @file:Suppress("IMPOSSIBLE_IS_CHECK_WARNING")
            class Box
            fun check(s: String) = s is Box
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0415", in: errorCtx)
    }
}
#endif
