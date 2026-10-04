// IndexOutOfBoundsException messages match the JVM ArrayList.
fun main() {
    val l = mutableListOf(1, 2, 3)
    try { l[5] } catch (e: IndexOutOfBoundsException) { println(e.message) }
    try { listOf(1, 2, 3)[5] } catch (e: IndexOutOfBoundsException) { println(e.message) }
    try { l.add(10, 0) } catch (e: IndexOutOfBoundsException) { println(e.message) }
    try { l[10] = 0 } catch (e: IndexOutOfBoundsException) { println(e.message) }
    try { l.removeAt(10) } catch (e: IndexOutOfBoundsException) { println(e.message) }
}
