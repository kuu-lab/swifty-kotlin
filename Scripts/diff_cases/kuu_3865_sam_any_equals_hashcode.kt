// KUU-3865: a `fun interface` whose only abstract member is a declared
// `Any.equals`/`Any.hashCode` gets a SAM wrapper that must answer the
// erased-Any dispatch tables (`kk_any_equals` / `kk_any_hashCode`), not
// only the interface itable. The null-literal `==` comparison must stay a
// raw `===`-style check that never consults the registered equals
// override, while `x == y` with a non-literal operand still dispatches
// through `Any.equals`.

fun interface E {
    override fun equals(other: Any?): Boolean
}

fun interface H {
    override fun hashCode(): Int
}

fun main() {
    val e = E { it -> it == null }
    val h = H { 42 }
    val a: Any = e
    val b: Any = h
    println(a.equals(e))   // erased-Any equals dispatch -> lambda sees e
    println(b.hashCode())  // erased-Any hashCode dispatch -> 42
    println(a.equals(null))
    println(a.equals(5))
    println(e == null)     // `===`-style null check, no equals dispatch
    val n: Any? = null
    println(e == n)        // areEqual -> e.equals(null)
    println(a.equals(b))
    println(e.equals(null))
    println(h.hashCode())
    println(b.equals(b))   // identity fallback, no equals override on H
}
