import kotlin.collections.AbstractMutableSet
import kotlin.collections.MutableSet
import kotlin.collections.Set

abstract class ProbeMutableSet : AbstractMutableSet<Int>()

fun acceptSet(values: Set<Int>) {}
fun acceptMutableSet(values: MutableSet<Int>) {}

fun probe(values: ProbeMutableSet) {
    acceptSet(values)
    acceptMutableSet(values)
}
