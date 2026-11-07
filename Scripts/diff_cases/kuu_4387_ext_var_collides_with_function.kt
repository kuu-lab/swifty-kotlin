// KUU-4387: an extension `var` whose name collides with a bundled collection
// function (`last()`, `first()`) must still bind as a property under
// property-access syntax. The collection member-call fast path claimed
// `l.last` for `last()` first, so the read was rejected with
// KSWIFTK-SEMA-0309 even though kotlinc resolves the extension property.
var MutableList<Int>.last: Int
    get() = this[size - 1]
    set(v) { this[size - 1] = v }

val List<Int>.first: Int
    get() = this[0]

fun main() {
    val l = mutableListOf(1, 2, 3)
    println(l.last)
    l.last = 9
    println(l)
    println(l.first)
    println(l.last())
}
