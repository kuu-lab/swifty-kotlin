// KSP-496 follow-up: a bare `::member` reference to a member property of the
// enclosing class is implicitly bound to `this` in Kotlin — it must capture
// the active receiver the same way an explicit `this::member` would, or
// .get()/.set() on the resulting KMutableProperty0 crash / read garbage.
class C(var v: Int) {
    fun bump() {
        val ref = ::v
        ref.set(ref.get() + 1)
    }
}

fun main() {
    val c = C(10)
    c.bump()
    println(c.v)
}
