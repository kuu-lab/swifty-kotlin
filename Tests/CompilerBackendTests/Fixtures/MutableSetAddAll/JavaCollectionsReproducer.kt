// Exact KUU-2154 reproducer; requires the Collections facade owned by KUU-2059.
import java.util.Collections
fun main() {
    val frozen = Collections.unmodifiableSet(mutableSetOf("a"))
    val mutable = Collections.newSetFromMap(mutableMapOf<String, Boolean>())
    try { println("frozen-sequence:${frozen.addAll(sequenceOf("x"))}") }
    catch (_: UnsupportedOperationException) { println("frozen-sequence:UOE") }
    println("mutable-sequence:${mutable.addAll(sequenceOf("x"))}:${mutable.size}")
    val iterable: Iterable<String> = listOf("x")
    try { println("frozen-iterable:${frozen.addAll(iterable)}") }
    catch (_: UnsupportedOperationException) { println("frozen-iterable:UOE") }
    println("mutable-iterable:${mutable.addAll(iterable)}:${mutable.size}")
}
