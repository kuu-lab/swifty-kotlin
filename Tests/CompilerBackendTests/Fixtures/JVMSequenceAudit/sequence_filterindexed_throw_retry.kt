fun main() {
var first = true
val iterator = sequenceOf(10, 20).filterIndexed { index, value -> println("$index:$value"); if (first) { first = false; throw IllegalArgumentException("once") }; true }.iterator()
try { iterator.hasNext() } catch (failure: IllegalArgumentException) { println("caught") }
println(iterator.next()); println(iterator.hasNext())
}
