@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct QualifiedNestedTypeArgumentValidationTests {
    @Test
    func importedAliasToInnerClassKeepsQualifierArguments() throws {
        let ctx = try semaContext(from: [
            """
            package model
            class Outer<T> { inner class Inner<U> }
            """,
            """
            package user
            import model.Outer as Renamed
            fun accept(value: Renamed<Int>.Inner<String>) {
                val cast = value as Renamed<Int>.Inner<String>
            }
            """,
        ], includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func importedAliasToStaticNestedClassRejectsQualifierArguments() throws {
        let ctx = try semaContext(
            from: [
                """
                package model
                class Outer<T> { class Nested<U> }
                """,
                """
                package user
                import model.Outer as Renamed
                fun accept(value: Renamed<Int>.Nested<String>) {}
                """,
            ],
            expecting: [
                .error(
                    "KSWIFTK-SEMA-0496",
                    containing: "Type arguments are not allowed for a non-inner nested class's qualifier"
                ),
            ],
            includeStdlib: false
        )

        #expect(ctx.diagnosticsWithCode("KSWIFTK-SEMA-0496", severity: .error).count == 1)
    }

    @Test
    func qualifiedTypeArgumentsAreCheckedPerSegment() throws {
        let ctx = try semaContext(
            from: """
            class Outer<T> { inner class Inner<U> }
            fun accept(value: Outer<Int, String>.Inner) {}
            """,
            expecting: [
                .error("KSWIFTK-SEMA-0497", containing: "expected 1 but got 2"),
            ],
            includeStdlib: false
        )

        #expect(ctx.diagnosticsWithCode("KSWIFTK-SEMA-0497", severity: .error).count == 1)
    }
}
