@testable import CompilerCore
import Testing

@Suite
struct DisjointEqualityTypeTests {
    @Test func rejectsUnrelatedFinalTypesButAllowsCommonSupertypes() throws {
        let sources = [
            """
            package invalid
            class First
            class Second
            fun compare(first: First, second: Second) = first == second
            fun compareRange(range: LongRange) = range == "x"
            fun compareNotEqual(first: First, second: Second) = first != second
            """,
            """
            package valid
            open class Base
            class Derived : Base()
            fun related(base: Base, derived: Derived) = base == derived
            fun erased(any: Any, text: String) = any == text
            fun nullable(first: String?, second: Int?) = first == second
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let invalid = diagnosticsForPath(paths[0], in: ctx)
            #expect(invalid.filter { $0.code == "KSWIFTK-SEMA-0002" }.count == 3)
            let valid = diagnosticsForPath(paths[1], in: ctx)
            #expect(valid.isEmpty, "Related and nullable types should remain comparable: \(valid)")
        }
    }
}
