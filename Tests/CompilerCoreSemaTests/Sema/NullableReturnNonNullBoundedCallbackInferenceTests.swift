#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NullableReturnNonNullBoundedCallbackInferenceTests {
    @Test
    func nullableReturnWithNonNullBoundInfersNonNullCallbackType() throws {
        _ = try semaContext(
            from: """
            interface Comparable<in T> {
                operator fun compareTo(other: T): Int
            }
            class Box : Comparable<Box> {
                override fun compareTo(other: Box): Int = 0
            }
            private fun <T : Comparable<T>> maxOrMin(elementAt: (Int) -> T): T? = null
            private fun <T : Comparable<T>> id(value: T): T? = value
            private fun <T> wrap(fn: () -> T): T? = null

            fun testCallbackNullableReturn(a: Box): Box? = maxOrMin { a }
            fun testCallbackNonNullAssertion(a: Box): Box = maxOrMin { a }!!
            fun testDirectNullableReturn(a: Box): Box? = id(a)
            fun testUnboundedNullableCallbackBody(): Box? = wrap { null }
            """,
            includeStdlib: false
        )
    }

    @Test
    func nullableReturnWithNonNullBoundStillRejectsUnboundedType() throws {
        _ = try semaContext(
            from: """
            interface Comparable<in T> {
                operator fun compareTo(other: T): Int
            }
            class Plain
            private fun <T : Comparable<T>> maxOrMin(elementAt: (Int) -> T): T? = null

            fun testInvalid(a: Plain): Plain? = maxOrMin { a }
            """,
            expecting: [.error("KSWIFTK-SEMA-BOUND")],
            includeStdlib: false
        )
    }
}
#endif
