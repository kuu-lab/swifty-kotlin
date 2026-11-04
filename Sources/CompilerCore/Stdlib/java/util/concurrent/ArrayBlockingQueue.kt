@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

// KUU-4047: java.util.concurrent.ArrayBlockingQueue — a capacity-bounded
// FIFO. The JVM class shares LinkedBlockingQueue's blocking contract
// (producers block while full, consumers block while empty, timed
// offer/poll give up after the timeout), so the implementation delegates
// by inheritance, the same delegation precedent ConcurrentSkipListSet
// uses over TreeSet.
//
// JVM parity notes:
//  - The JVM `fair` constructor flag is accepted for API parity; the
//    single-guard implementation is already fair to waiters in the
//    LinkedBlockingQueue sense, so the flag is intentionally unobserved.
//  - `is java.util.concurrent.LinkedBlockingQueue<E>` answers true on
//    these instances; on the JVM it is false but the source-level check
//    is a compile error there (the same caveat ConcurrentSkipListSet
//    documents for TreeSet).
public class ArrayBlockingQueue<E> : LinkedBlockingQueue<E> {
    public constructor(capacity: Int) : super(capacity)

    public constructor(capacity: Int, fair: Boolean) : super(capacity)

    public constructor(capacity: Int, fair: Boolean, elements: Collection<E>) : super(capacity) {
        // JVM requires capacity >= elements.size; LinkedBlockingQueue's add
        // would surface IllegalStateException partway through instead, so
        // pre-check to report the JVM IllegalArgumentException.
        if (elements.size > capacity) throw IllegalArgumentException("capacity < collection size")
        addAll(elements)
    }
}
