// DIFF_JVM
class P(val v: Int) { operator fun rangeTo(o: P) = v + o.v }
class Label(val value: String) { override fun toString(): String = value }
class Q(val v: Int) {
    operator fun rangeTo(other: Q): Label = Label("sum=${v + other.v}")
}
class Indices(val value: Int) {
    operator fun rangeTo(other: Indices): IntArray = intArrayOf(value, other.value)
}

fun main() {
    println(P(1)..P(2))
    val sum = P(3)..P(4)
    println(sum)
    println(Q(3)..Q(4))
    val label = Q(5)..Q(6)
    println(label)
    for (index in Indices(5)..Indices(6)) println(index)
    println(1..3)
}
