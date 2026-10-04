class Plain(val n: Int)
data class Data(val n: Int)

fun main() {
    val plainA = Plain(1)
    val plainB = Plain(1)
    // Default Any.equals is reference identity for ordinary classes.
    println(plainA == plainB)

    val anyA: Any = plainA
    val anyB: Any = plainB
    println(anyA == anyB)
    println(anyA.equals(anyB))

    val dataA = Data(1)
    val dataB = Data(1)
    println(dataA == dataB)
    println(dataA.equals(dataB))

    val anyDataA: Any = dataA
    val anyDataB: Any = dataB
    println(anyDataA == anyDataB)
    println(anyDataA.equals(anyDataB))
}
