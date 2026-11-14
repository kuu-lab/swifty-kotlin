package kotlin.collections

public abstract class LongIterator: Iterator<Long>, kotlin.jvm.internal.markers.KMappedMarker {
    public fun remove() { throw UnsupportedOperationException("Operation is not supported for read-only collection") }
    public abstract override operator fun hasNext(): Boolean
    public abstract fun nextLong(): Long
    final override operator fun next(): Long = nextLong()
    // Kotlin/JVM consumers call the boxed covariant next descriptor.
    @kotlin.jvm.JvmName("next") public fun boxedNext(): Long? = nextLong()
}
