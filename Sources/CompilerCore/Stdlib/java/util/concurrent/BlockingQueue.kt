package java.util.concurrent

import java.util.Queue

public interface BlockingQueue<E> : Queue<E> {
    public fun put(element: E): Unit

    public fun take(): E

    public fun offer(element: E, timeout: Long, unit: TimeUnit): Boolean

    public fun poll(timeout: Long, unit: TimeUnit): E?

    public fun remainingCapacity(): Int

    public fun drainTo(target: MutableCollection<in E>): Int

    public fun drainTo(target: MutableCollection<in E>, maxElements: Int): Int
}
