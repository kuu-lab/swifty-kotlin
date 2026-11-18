#if canImport(Testing)
import Testing
@testable import CompilerTestSupport

@Suite
struct NothingNullAssertMemberTests {
    // KUU-4593: a `!!` on a definitely-null reference types the receiver
    // itself as `Nothing`, but kotlinc resolves member accesses on that
    // receiver against the asserted declared type — the operand's declared
    // type made non-null.
    @Test
    func memberAccessOnDefinitelyNullNullAssertResolvesAgainstAssertedType() throws {
        _ = try semaContext(from: """
        class Box(val foo: Int) {
            fun bar(): Int = foo
        }
        fun property() {
            var b: Box? = Box(1)
            b = null
            val x: Int = b!!.foo
        }
        fun function() {
            var b: Box? = Box(1)
            b = null
            val y: Int = b!!.bar()
        }
        fun parameter(b: Box?) {
            val p: Int = b!!.foo
            val q: Int = b!!.bar()
        }
        """, includeStdlib: false)
    }

    // KUU-4593: the asserted-type receiver rule applies to direct member
    // access only. kotlinc still rejects `(b!!)?.foo` on a definitely-null
    // `b`, so the safe-call path keeps the `Nothing` receiver.
    @Test
    func safeCallOnDefinitelyNullNullAssertStaysUnresolved() throws {
        _ = try semaContext(from: """
        class Box(val foo: Int) {
            fun bar(): Int = foo
        }
        fun property() {
            var b: Box? = Box(1)
            b = null
            val x: Int? = (b!!)?.foo
        }
        fun function() {
            var b: Box? = Box(1)
            b = null
            val y: Int? = (b!!)?.bar()
        }
        """, expecting: [
            .error("KSWIFTK-SEMA-0024", containing: "Unresolved member function 'foo'"),
            .error("KSWIFTK-SEMA-0024", containing: "Unresolved member function 'bar'"),
        ], includeStdlib: false)
    }
}
#endif
