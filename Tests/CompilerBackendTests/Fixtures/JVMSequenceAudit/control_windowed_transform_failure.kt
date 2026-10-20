fun main() {
var first = true
val iterator = sequenceOf(1, 2, 3).windowed(2, 1, true) { if (first) { first = false; throw IllegalArgumentException("once") }; it.joinToString(":") }.iterator()
try { iterator.next() } catch (failure: IllegalArgumentException) { println("caught") }
println(iterator.hasNext()); println(iterator.next()); println(iterator.next()); println(iterator.hasNext())
}
