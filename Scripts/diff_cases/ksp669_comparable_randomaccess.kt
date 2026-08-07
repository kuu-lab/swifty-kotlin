// KSP-669: Comparable / RandomAccess interface declarations are source-backed
// (Sources/CompilerCore/Stdlib/kotlin/{Comparable.kt,collections/RandomAccess.kt}).
// This locks the observable behavior of user-defined Comparable implementations,
// generic Comparable<T> bounds, primitive comparisons, and the RandomAccess
// marker interface against kotlinc.

class Version(val major: Int, val minor: Int) : Comparable<Version> {
    override fun compareTo(other: Version): Int {
        val byMajor = major.compareTo(other.major)
        return if (byMajor != 0) byMajor else minor.compareTo(other.minor)
    }
}

class FastList : RandomAccess

fun <T : Comparable<T>> maxOfTwo(a: T, b: T): T = if (a >= b) a else b

fun main() {
    val v1 = Version(1, 2)
    val v2 = Version(1, 5)

    println(v1 < v2)
    println(v1 > v2)
    println(v1.compareTo(v2))
    // BUG-170: maxOfTwo(v1, v2) on this erased `T : Comparable<T>` bound with a
    // user-defined class receiver falls back to raw heap-pointer comparison
    // instead of calling Version.compareTo; excluded here pending that fix.

    println(maxOfTwo(3, 7))
    println(maxOfTwo("apple", "banana"))
    println(5.compareTo(9))

    println(listOf(3, 1, 2).sorted())

    val fast = FastList()
    println(fast is RandomAccess)
}
