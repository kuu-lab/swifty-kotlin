package java.util

// KUU-3059: java.util.Queue — the FIFO collection contract shared by
// java.util.concurrent.ConcurrentLinkedQueue and friends.
public interface Queue<E> : MutableCollection<E> {
    public fun offer(element: E): Boolean

    public fun poll(): E?

    public fun element(): E

    public fun peek(): E?
}
