package java.util

public interface Queue<E> : MutableCollection<E> {
    public fun offer(element: E): Boolean

    public fun poll(): E?

    public fun element(): E

    public fun peek(): E?

    public fun remove(): E
}
