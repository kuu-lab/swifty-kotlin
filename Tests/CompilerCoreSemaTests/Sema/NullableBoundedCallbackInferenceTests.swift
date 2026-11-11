#if canImport(Testing)
import Testing
@testable import CompilerTestSupport

@Suite
struct NullableBoundedCallbackInferenceTests {
    @Test
    func nullableExpectedResultKeepsNonNullCallbackBound() throws {
        _ = try semaContext(from: """
        class Ranked : Comparable<Ranked> {
            override fun compareTo(other: Ranked): Int = 0
        }
        fun <T : Comparable<T>> pick(make: () -> T): T? = make()
        fun <T : Comparable<T>> create(): T = Ranked() as T

        fun exact(): Ranked? = pick { Ranked() }
        fun wider(): Comparable<Ranked>? = pick { Ranked() }
        fun nested(): Ranked? = pick { create() }
        """, includeStdlib: false)
    }

    @Test
    func nullableCallbackStillCannotSatisfyNonNullBound() throws {
        _ = try semaContext(from: """
        fun <T : Any> pick(make: () -> T): T? = make()
        fun invalid(): String? = pick { null }
        """, expecting: [.error("KSWIFTK-SEMA-0469")], includeStdlib: false)
    }
}
#endif
