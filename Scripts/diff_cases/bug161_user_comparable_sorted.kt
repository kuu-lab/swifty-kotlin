// BUG-161: sorting collections of user-defined Comparable implementations used
// to crash with SIGSEGV because the runtime dispatched `compareTo` through a
// two-argument function pointer while compiler-emitted members take
// (receiver, args..., outThrown) and may return a boxed Int.

class Version(val major: Int, val minor: Int) : Comparable<Version> {
    override fun compareTo(other: Version): Int {
        val byMajor = major.compareTo(other.major)
        return if (byMajor != 0) byMajor else minor.compareTo(other.minor)
    }
}

interface Tagged {
    fun tag(): String
}

// Comparable is not the first implemented interface, so the itable slot must be
// resolved from the object's own registration.
class Boxed(val n: Int) : Tagged, Comparable<Boxed> {
    override fun tag(): String = "B$n"
    override fun compareTo(other: Boxed): Int = if (n < other.n) -1 else if (n > other.n) 1 else 0
}

fun main() {
    val versions = listOf(Version(1, 5), Version(1, 2), Version(0, 9))
    println(versions.sorted().map { "${it.major}.${it.minor}" })
    println(versions.sortedDescending().map { "${it.major}.${it.minor}" })
    println(versions.sortedBy { it }.map { "${it.major}.${it.minor}" })
    println(versions.sortedWith(compareBy { it }).map { "${it.major}.${it.minor}" })

    val boxes = listOf(Boxed(3), Boxed(1), Boxed(2))
    println(boxes.sorted().map { it.n })
    println(boxes.sortedDescending().map { it.tag() })

    val mutable = mutableListOf(Version(2, 0), Version(1, 0))
    mutable.sort()
    println(mutable.map { it.major })

    println(listOf(3, 1, 2).sorted())
    println(listOf("b", "a").sorted())
}
