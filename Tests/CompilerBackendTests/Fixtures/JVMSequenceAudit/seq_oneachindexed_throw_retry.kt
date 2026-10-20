
fun main() {
var first = true
val iterator = sequenceOf(10, 20).onEachIndexed { index, value -> println("$index:$value"); if (first) { first = false; throw IllegalStateException("once") } }.iterator()
try { iterator.next() } catch (failure: IllegalStateException) { println("caught") }
println(iterator.next()); println(iterator.hasNext())
}
