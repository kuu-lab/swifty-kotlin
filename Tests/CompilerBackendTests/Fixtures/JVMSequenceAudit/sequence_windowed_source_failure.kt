fun main() {
var first = true
val source = sequenceOf(1, 2, 3).map { if (it == 2 && first) { first = false; throw IllegalArgumentException("once") }; it }
val iterator = source.windowed(2).iterator()
try { iterator.hasNext() } catch (failure: IllegalArgumentException) { println("caught") }
try { println(iterator.hasNext()) } catch (failure: IllegalStateException) { println("failed") }
}
