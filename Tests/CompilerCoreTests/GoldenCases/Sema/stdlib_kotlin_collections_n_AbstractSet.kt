package golden.sema

import kotlin.collections.AbstractSet
import kotlin.collections.Collection
import kotlin.collections.Set

// KSP-932: the nominal AbstractSet class shell is source-backed.
abstract class ProbeSet : AbstractSet<Int>()

fun acceptCollection(values: Collection<Int>) {}

fun acceptSet(values: Set<Int>) {}

fun probe(values: ProbeSet) {
    acceptCollection(values)
    acceptSet(values)
}
