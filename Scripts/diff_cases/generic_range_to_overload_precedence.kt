// DIFF_JVM
class MyRange<T>(val a: T, val b: T) { override fun toString(): String = "My($a,$b)" }
operator fun <T : Comparable<T>> T.rangeTo(that: T): MyRange<T> = MyRange(this, that)

fun main() {
    println(true..false)
    println(true..true)
    println(1..2)
    println('a'..'c')
}
