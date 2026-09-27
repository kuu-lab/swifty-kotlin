@testable import CompilerCore
import Testing

@Suite
struct DisjointEqualityTypeTests {
    @Test func matchesKotlinBuiltinEqualityCompatibility() throws {
        let sources = [
            """
            package invalid
            class Custom
            fun compareRange(range: LongRange) = range == "x"
            fun nullable(first: String?, second: Int?) = first == second
            fun numeric(first: Int, second: Long) = first != second
            fun custom(first: Custom, second: String) = first == second
            fun explicitCast(value: Any, text: String) = (value as Int) == text
            """,
            """
            package valid
            class First
            class Second
            fun classes(first: First, second: Second) = first == second
            fun nullableClasses(first: First?, second: Second?) = first != second
            open class Base
            class Derived : Base()
            fun related(base: Base, derived: Derived) = base == derived
            fun erased(any: Any, text: String) = any == text
            fun nullable(any: Any?, text: String?) = any == text
            fun same(first: String?, second: String?) = first == second
            fun nullLiteral(text: String?) = text == null
            fun nullLeft(text: String?) = null == text
            fun nullableRelated(base: Base?, derived: Derived?) = base == derived
            interface Marker
            class Plain
            fun interfaceFinal(marker: Marker, plain: Plain) = marker == plain
            class Other
            fun openFinal(base: Base, other: Other) = base == other
            fun ranges(first: IntRange, second: LongRange) = first == second
            fun <T> generic(value: T, number: Int) = value == number
            fun <T : Any> nonNullGeneric(value: T, number: Int) = value == number
            fun comparable(text: String, other: Comparable<Int>) = text == other
            fun comparableNumber(number: Int, other: Comparable<String>) = number == other
            fun narrowed(value: Any, text: String): Boolean {
                if (value is Int) return value == text
                return false
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let invalid = diagnosticsForPath(paths[0], in: ctx)
            #expect(invalid.filter { $0.code == "KSWIFTK-SEMA-0002" }.count == 5)
            let valid = diagnosticsForPath(paths[1], in: ctx)
            #expect(valid.isEmpty, "Compatible equality operands should remain accepted: \(valid)")
        }
    }
}
