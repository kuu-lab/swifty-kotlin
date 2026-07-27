// BUG-043: methods on the implicit StringBuilder receiver inside
// buildString { ... } / buildStringBuilder { ... } other than the six that used
// to be rewritten to the global builder-state DSL used to run with an invalid
// `this` handle (0). Pin the previously-broken methods through the builder lambda.
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
    println(buildStringBuilder { append("hi"); reverse() }.toString())
}
