package kotlin.collections

public interface Iterator<out T> {
    public operator fun next(): T
    public operator fun hasNext(): Boolean
}
