import kotlin.collections.AbstractSet
import kotlin.collections.Set

// KSP-932: keep the minimal subclass and Set semantics in the executable diff.
abstract class ProbeSet : AbstractSet<Int>()

fun main() {
    val ordered: Set<Int> = setOf(1, 2, 3)
    val reordered: Set<Int> = setOf(3, 1, 2)
    val withDuplicates: Set<Int> = setOf(1, 1, 2, 3)
    val differentType: Set<String> = setOf("1", "2", "3")

    println(ordered == reordered)
    println(ordered == withDuplicates)
    println((ordered as Any) == differentType)
    println((ordered as Any) == listOf(1, 2, 3))
    println(withDuplicates.size)
    println(ordered.hashCode())
    println(reordered.hashCode())
    println(ordered.contains(2))
    println(ordered.contains(9))
}
