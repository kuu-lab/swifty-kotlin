package kotlin.sequences

public interface Sequence<out T> {
    public operator fun iterator(): Iterator<T>
}
