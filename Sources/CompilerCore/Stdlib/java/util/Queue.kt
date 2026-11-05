package java.util

// KUU-3059: java.util.Queue — the FIFO collection contract shared by
// java.util.concurrent.ConcurrentLinkedQueue and friends.
// KUU-3996: the no-arg remove() is declared on the JVM Queue interface
// (head removal, NoSuchElementException when empty), alongside the
// Collection.remove(element) overload inherited from MutableCollection.
public interface Queue<E> : MutableCollection<E> {
    public fun offer(element: E): Boolean

    public fun poll(): E?

    public fun element(): E

    public fun peek(): E?

    public fun remove(): E
}
