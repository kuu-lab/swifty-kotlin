fun visit(key: String, value: Int) { println("$key$value") }
fun pair2(a: Double, b: Boolean) { println("pair2:$a=$b") }
fun inc(x: Int): Int = x + 1

inline fun <K, V> visitPair(key: K, value: V, action: (K, V) -> Unit) {
    action(key, value)
}
inline fun <T> applyTwice(x: T, f: (T) -> T): T = f(f(x))

fun main() {
    val stored = ::visit
    visitPair("a", 1, ::visit)
    visitPair("b", 2, stored)
    visitPair("c", 3) { key, value -> println("$key$value") }
    val label = "cap:"
    visitPair("d", 4) { k, v -> println("$label$k$v") }
    val storedLambda: (String, Int) -> Unit = { k, v -> println("stored:$k=$v") }
    visitPair("e", 5, storedLambda)
    visitPair(1.5, true, ::pair2)
    val pairStored = ::pair2
    visitPair(2.5, false, pairStored)
    println(applyTwice(3, ::inc))
    val incStored = ::inc
    println(applyTwice(4, incStored))
}
