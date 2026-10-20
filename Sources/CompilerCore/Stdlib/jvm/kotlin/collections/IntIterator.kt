package kotlin.collections

public abstract class IntIterator: Iterator<Int>, kotlin.jvm.internal.markers.KMappedMarker {
    public fun remove() { throw UnsupportedOperationException("Operation is not supported for read-only collection") }
    public abstract override operator fun hasNext(): Boolean
    public abstract fun nextInt(): Int
    final override operator fun next(): Int = nextInt()
    // Kotlin/JVM consumers call the boxed covariant next descriptor.
    @kotlin.jvm.JvmName("next") public fun boxedNext(): Int? = nextInt()
}
