// EXPECT-REJECT
// KUU-996: non-property primary-constructor parameters are scoped to
// `init {}` blocks and property initializers only. Member functions,
// `this.x`, secondary-constructor bodies, and inner/nested class members
// must all fail to resolve them — verified against kotlinc 2.3.10 and
// 2.4.20, which report errors on exactly the same lines.
class Box(x: Int) {
    val doubled = x * 2
    init { println(x) }
    fun get() = x
    fun getThis() = this.x
}
class Two(x: Int) {
    constructor(y: String) : this(y.length) { println(x) }
}
class Outer(x: Int) {
    inner class Inner { fun get() = x }
    class Nested { fun get() = x }
}
fun main() { println(Box(3).doubled) }
