// BUG-043: methods on the implicit StringBuilder receiver inside
// buildString { ... } other than the six that used to be rewritten to the global
// builder-state DSL used to run with an invalid `this` handle (0). Pin the
// previously-broken methods through the builder lambda. (`buildStringBuilder` is a
// kswiftk-only helper absent from JVM kotlinc, so it is exercised only in the
// Codegen integration test, not in this kotlinc-parity diff case.)
fun main() {
    println(buildString { append("x"); reverse() })
    println(buildString { append("abc"); reverse() })
    println(buildString { append("abc"); clear(); append("z") })
    println(buildString { append("abc"); deleteAt(1) })
    println(buildString { append("abc"); deleteCharAt(0) })
    println(buildString { append("abc"); setCharAt(1, 'Y') })
    println(buildString { append("abc"); set(2, 'Z') })
    println(buildString { append("abc"); append(get(1)) })
    println(buildString { append("abcd"); setRange(1, 3, "XY") })
    println(buildString { append("abcd"); deleteRange(1, 3) })
    println(buildString { append("hello"); append(toString().length) })
}
