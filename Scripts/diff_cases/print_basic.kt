// KSP-614: kotlin.io.print / println are implemented in Kotlin
// (Stdlib/kotlin/io/Console.kt) on top of the single __kk_print_raw bridge.
enum class Color { RED, GREEN }
data class P(val a: Int, val b: String)
class C { override fun toString(): String = "C!" }
data object DO

fun main() {
    println()
    println("hello")
    print("no-newline")
    println()
    println(42)
    println(42L)
    println(3.5)
    println(3.5f)
    println('x')
    println(true)
    println(null)
    val a: Any? = null
    println(a)
    println(listOf(1, 2, 3))
    println(setOf(1, 2))
    println(mapOf(1 to "a"))
    println(1 to 2)
    println(Triple(1, 2, 3))
    println(1..3)
    println(Color.RED)
    println(Color.RED.name)
    println(P(1, "x"))
    println(C())
    println(DO)
    val n: C? = null
    println(n)
    val s: String? = "abc"
    println(s)
    println("interp ${1 + 1}")
    print(listOf(1, 2))
    println()
    print(Color.GREEN)
    println()
    println(1.toString())
    val u: ULong = 18446744073709551615uL
    println(u)
    println(StringBuilder("sb"))
}
