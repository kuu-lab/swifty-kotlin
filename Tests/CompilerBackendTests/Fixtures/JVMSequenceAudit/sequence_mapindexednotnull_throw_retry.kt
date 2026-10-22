fun main() {
var first = true
val iterator = sequenceOf(10, 20).mapIndexedNotNull { index, value -> if (first) { first = false; throw IllegalArgumentException("once") }; "$index:$value" }.iterator()
try { iterator.hasNext() } catch (failure: IllegalArgumentException) { println("caught") }
println(iterator.next()); println(iterator.hasNext())
}
