// DIFF_JVM
// KUU-1938: Nullable builtins implement nullable Comparable of their non-null type.
fun intComparable(value: Int?): Comparable<Int>? = value
fun stringComparable(value: String?): Comparable<in String>? = value

fun main() {
    val i: Int? = 3
    val c: Comparable<Int>? = i
    val s: String? = "x"
    val d: Comparable<in String>? = s
    println(c == null)
    println(d == null)
    println(intComparable(3) == null)
    println(intComparable(null) == null)
    println(stringComparable("x") == null)
    println(stringComparable(null) == null)
}
