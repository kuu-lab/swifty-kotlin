@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct SamConstructorComparatorDispatchTests {
    @Test
    func callableReferenceComparatorDispatchesInsideSortedWith() throws {
        try compileAndRunKotlin(
            try diffCaseSource("sam_constructor_callable_ref.kt", file: #filePath),
            expectedOutput: "-2\n-2\n98\nv=42\n[1, 3, 5]\n[2, 4, 9]\n",
            moduleName: "KUU2407SamConstructorCallableReference",
            expectedStderr: ""
        )
    }

    @Test
    func functionValueComparatorDispatchesInsideSortedWith() throws {
        try compileAndRunKotlin(
            try diffCaseSource("sam_constructor_function_value.kt", file: #filePath),
            expectedOutput: "v=42\n-2\n[2, 4, 9]\n",
            moduleName: "KUU2407SamConstructorFunctionValue",
            expectedStderr: ""
        )
    }

    @Test
    func comparableMethodReferenceDispatchesInsideNullsFirst() throws {
        let source = """
        class Ranked(val value: Int) : Comparable<Ranked> {
            override fun compareTo(other: Ranked): Int = other.value - value
        }

        fun main() {
            val cmp = Comparable<Ranked>::compareTo
            val comparator = nullsFirst(cmp)
            println(comparator.compare(Ranked(1), Ranked(2)) > 0)
            println(comparator.compare(Ranked(2), Ranked(1)) < 0)
            println(comparator.compare(Ranked(2), Ranked(2)) == 0)
            println(comparator.compare(null, Ranked(1)) == -1)
            println(comparator.compare(Ranked(1), null) == 1)
        }
        """
        try compileAndRunKotlin(
            source,
            expectedOutput: "true\ntrue\ntrue\ntrue\ntrue\n",
            moduleName: "KUU3293ComparableCallableReferenceNullsFirst",
            expectedStderr: ""
        )
    }
}
