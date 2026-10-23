// KUU-3027: a boxed enum entry must not compare equal to a raw Int carrying
// the same ordinal — JVM `Enum.equals` is final reference identity, so
// `(E.A as Any) == 0` is false. Collection membership must keep working
// whether the probe argument arrives boxed or as a bare ordinal.

enum class E { A, B, C }

enum class F { A, B }

fun <T> containsIn(coll: Collection<T>, element: T): Boolean = coll.contains(element)

fun main() {
    // Erased == against scalars (JVM: all false).
    println((E.A as Any) == 0)
    println((E.B as Any) == 1)
    println((E.A as Any) == 0L)
    // Erased == against other values.
    println((E.A as Any) == (E.A as Any))
    println((E.A as Any) == (E.B as Any))
    println((E.A as Any) == (F.A as Any))
    println((E.A as Any) == "A")
    // Nullable enum slot vs erased box.
    val nullable: E? = E.A
    val absent: E? = null
    println((nullable as Any) == 0)
    println((nullable as Any) == (E.A as Any))
    // Nullable enum == non-null enum keeps comparing entries by value.
    println(nullable == E.A)
    println(E.A == nullable)
    println(nullable == E.B)
    println(absent == E.A)
    println(nullable == absent)
    println(absent == absent)
    println(nullable == nullable)
    // Non-null enum entry vs erased peers.
    println((E.A as Any) == E.A)
    println(E.A == (E.A as Any))
    println(E.A == (0 as Any))
    println(nullable == (0 as Any))
    println(nullable == (E.A as Any))
    // equals() / Objects.deepEquals parity.
    println((E.A as Any).equals(0))
    println(java.util.Objects.deepEquals((E.A as Any), 0))
    println(java.util.Objects.deepEquals((E.A as Any), (E.A as Any)))
    // Erased structural equality inside containers.
    println(listOf(E.A as Any) == listOf(0 as Any))
    println(listOf(E.A) == listOf(E.A))
    // Collection membership keeps matching enum elements.
    val set = hashSetOf(E.A, E.B)
    println(set.contains(E.A))
    println(set.contains(E.B))
    println(set.contains(E.C))
    println(set.remove(E.B))
    println(set.contains(E.B))
    val map = hashMapOf(E.A to 1, E.C to 3)
    println(map[E.A])
    println(map[E.C])
    println(map.remove(E.A))
    println(map[E.A])
    val list = mutableListOf(E.A, E.C)
    println(list.contains(E.A))
    println(list.indexOf(E.C))
    println(list.remove(E.A))
    println(list.contains(E.A))
    // Generic boundary dispatch must carry the enum box end to end.
    println(containsIn(set, E.A))
    println(containsIn(set, E.C))
    // Membership on interface-typed receivers.
    val asSet: Set<E> = set
    println(E.A in asSet)
    println(E.C in asSet)
    // Sequence scans.
    println(sequenceOf(E.A, E.B).contains(E.B))
    println(sequenceOf(E.A, E.B).indexOf(E.A))
    // Set equality still structural.
    println(setOf(E.A) == setOf(E.A))
    println(setOf(E.A) == setOf(E.B))
    // A plain boxed Int in a heterogeneous set stays distinct from an enum
    // entry of the same ordinal (JVM parity: they are not equal elements).
    val mixed: MutableSet<Any> = hashSetOf(E.A as Any, 0 as Any)
    println(mixed.size)
    // Scalar probes must not alias the stored enum box (JVM: all false/-1).
    println(0 in listOf<Any>(E.A, 5))
    println(0 in setOf<Any>(E.A, 5))
    println(listOf<Any>(E.A, 5).indexOf(0))
    println(sequenceOf<Any>(E.A, 7).contains(0))
    println(sequenceOf<Any>(E.A, 7).indexOf(0))
    val erased = mutableListOf<Any>(E.A, 5)
    println(erased.remove(0))
    println(erased)
    // Enum and plain-int probes keep matching their own elements.
    println(E.A in listOf<Any>(E.A, 5))
    println(5 in listOf<Any>(E.A, 5))
    println(listOf<Any>(E.A, 5).indexOf(E.A))
    println(erased.remove(E.A))
    println(erased)
}
