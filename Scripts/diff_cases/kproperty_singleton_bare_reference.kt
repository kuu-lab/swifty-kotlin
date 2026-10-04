// KSP-505 (KSP-496 follow-up): a bare `::member` reference to a property
// owned by a singleton (companion object or plain top-level `object`) used
// to crash with SIGSEGV once its type-checked as KProperty0/KMutableProperty0
// (previously kept as a compile-time type-mismatch instead, precisely to
// avoid this). Root cause: unlike a `.class` instance, a singleton's
// properties are stored in a single module-level global slot rather than a
// per-instance field, and the singleton "instance" itself is frequently a
// null placeholder (no real heap object is allocated for a companion/object
// that implements no interface and declares no virtual dispatch) — so
// capturing and dereferencing a receiver for it crashed. The fix makes the
// generated KProperty wrapper read/write the global slot directly, the same
// way an ordinary (non-callable-ref) read of the property already did, with
// no receiver capture at all. Also covers an explicit singleton-qualified
// reference (`Foo::topLevelObjectProp`), which hit the same crash via a
// different (non-bare, receiver-capturing-by-default) code path.
import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KProperty0

class C {
    companion object {
        val constVal: Int = 5
        var mutableVal: Int = 10

        fun readConst(): Int {
            val ref: KProperty0<Int> = ::constVal
            return ref.get()
        }

        fun readWriteMutable(): Int {
            val ref: KMutableProperty0<Int> = ::mutableVal
            ref.set(ref.get() + 1)
            return ref.get()
        }
    }
}

object TopLevelObject {
    val objectVal: Int = 42
}

fun main() {
    println(C.readConst())
    println(C.readWriteMutable())
    println(C.Companion.mutableVal)

    val objectRef: KProperty0<Int> = TopLevelObject::objectVal
    println(objectRef.get())
}
