
fun main() {
var first = true
val iterator = sequenceOf(1, 2, 3).zipWithNext { a, b -> if (first) { first = false; throw IllegalArgumentException("once") }; "$a:$b" }.iterator()
try { iterator.next() } catch (failure: IllegalArgumentException) { println("caught") }
try { println(iterator.next()) } catch (failure: IllegalStateException) { println("failed") }
}
