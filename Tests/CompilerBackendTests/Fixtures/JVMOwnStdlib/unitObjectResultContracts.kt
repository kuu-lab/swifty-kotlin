fun report(block: () -> Any?) { println(block()) }
fun <T> invokeUnitFactory(block: () -> T): T = block()
fun expressionResult(): Any? = println("expression")
fun nonNullResult(): Any = println("nonnull")
fun explicitReturn(): Any? { return println("return") }
fun discarded() { println("discarded") }
fun main() {
    println(expressionResult())
    println(nonNullResult())
    println(explicitReturn())
    println(invokeUnitFactory<Any?>({ println("generic") }))
    report { mutableListOf<Int>().clear() }
    val callback: () -> Unit = { println("unit-callback") }
    println(callback())
    report { println("one"); println("two") }
    report { val value: Unit? = null; value }
    discarded()
    try { report { println("throw"); throw IllegalStateException("stop") } }
    catch (e: IllegalStateException) { println(e.message) }
}
