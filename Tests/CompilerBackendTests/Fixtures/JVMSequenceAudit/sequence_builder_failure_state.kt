
fun main() {
val iterator = sequence<Int> { try { yield(1); throw IllegalArgumentException("broken") } finally { println("finally") } }.iterator(); println(iterator.next()); try { iterator.hasNext() } catch (failure: IllegalArgumentException) { println("first") }; try { iterator.hasNext() } catch (failure: IllegalStateException) { println("failed") }
}
