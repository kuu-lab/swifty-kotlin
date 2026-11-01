package java.util.concurrent

import java.util.Queue

// KUU-4032: java.util.concurrent.BlockingQueue — the bounded FIFO contract
// implemented by LinkedBlockingQueue. Producers block in `put` while the
// queue is full and consumers block in `take` while it is empty; the timed
// `offer`/`poll` overloads give up after the supplied timeout.
public interface BlockingQueue<E> : Queue<E> {
    public fun put(element: E): Unit

    public fun take(): E

    public fun offer(element: E, timeout: Long, unit: TimeUnit): Boolean

    public fun poll(timeout: Long, unit: TimeUnit): E?

    public fun remainingCapacity(): Int

    public fun drainTo(target: MutableCollection<in E>): Int

    public fun drainTo(target: MutableCollection<in E>, maxElements: Int): Int
}
