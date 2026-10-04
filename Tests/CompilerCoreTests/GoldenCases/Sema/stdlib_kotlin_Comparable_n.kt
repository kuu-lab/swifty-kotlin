package golden.sema

class Version(val value: Int) : Comparable<Version> {
    override fun compareTo(other: Version): Int = value.compareTo(other.value)
}

fun <T : Comparable<T>> compareBound(a: T, b: T): Int = a.compareTo(b)

fun comparePrimitive(a: Int, b: Int): Int = a.compareTo(b)
