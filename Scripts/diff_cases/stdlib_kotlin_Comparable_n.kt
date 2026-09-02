class Version(val value: Int) : Comparable<Version> {
    override fun compareTo(other: Version): Int = value.compareTo(other.value)
}

fun <T : Comparable<T>> compareBound(a: T, b: T): Int = a.compareTo(b)

fun main() {
    println(Version(1).compareTo(Version(2)))
    println(compareBound(3, 7))
    println(5.compareTo(9))
}
