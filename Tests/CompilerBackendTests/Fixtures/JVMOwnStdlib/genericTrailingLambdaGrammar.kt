inline fun <T> evaluate(block: () -> T): T = block()
fun <K, V> result(block: () -> V): V = block()
class Receiver { fun <T> member(block: () -> T): T = block() }
fun nonLocal(): Int {
    evaluate<Int> { return 11 }
    return -1
}
fun main() {
    println(evaluate<Int> { 7 })
    println(result<Int, String> { "two" })
    println(Receiver().member<Int> { 9 })
    println(evaluate<Int> marked@ { return@marked 12 })
    println(evaluate<Int>() marked@ { return@marked 13 })
    println(evaluate<Int> { return@evaluate 14 })
    println(nonLocal())
    println(1 < 2)
    println(3 > 2)
}
