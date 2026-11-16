package kotlin.collections

public abstract class CharIterator : Iterator<Char>, kotlin.jvm.internal.markers.KMappedMarker {
    public fun remove() {
        throw UnsupportedOperationException("Operation is not supported for read-only collection")
    }

    public abstract override operator fun hasNext(): Boolean
    public abstract fun nextChar(): Char
    final override operator fun next(): Char = nextChar()

    @kotlin.jvm.JvmName("next")
    public fun boxedNext(): Char? = nextChar()
}
