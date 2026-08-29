// Regression for a bug where a constructor/function parameter whose name is
// literally a Kotlin modifier keyword (`inner`, `sealed`, `operator`, `override`,
// `vararg`, ...) was silently dropped during AST construction: these keywords
// are valid plain identifiers outside modifier position, but the parser
// unconditionally rejected them as parameter names.
data class Box(val x: Int)
data class Holder(val inner: Box, val tag: Int)

class Config(val sealed: Int, val operator: Int, val override: Int) {
    fun total(): Int = sealed + operator + override
}

fun withKeywordNames(inner: Int, sealed: Int, vararg: Int): Int = inner + sealed + vararg

fun realVarargStillWorks(vararg nums: Int): Int {
    var total = 0
    for (n in nums) total += n
    return total
}

interface Named { val name: String }
class Person(override val name: String) : Named

fun main() {
    val h = Holder(Box(1), 2)
    println(h.inner.x)
    println(h.tag)

    val c = Config(10, 20, 30)
    println(c.total())

    println(withKeywordNames(1, 2, 3))
    println(realVarargStillWorks(1, 2, 3))
    println(Person("Alice").name)
}
