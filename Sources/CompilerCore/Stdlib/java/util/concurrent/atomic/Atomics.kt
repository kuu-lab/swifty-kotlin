package java.util.concurrent.atomic

// KUU-3059: member surface beyond the runtime-backed cores registered in
// registerSyntheticAtomicResidualStubs. AtomicBoolean and AtomicReference
// have no kk_atomic_*_compareAndSet export, so their CAS wraps
// compareAndExchange exactly like kotlin.concurrent does in
// AtomicMigration.kt (AtomicReference compares references by identity).
// lazySet/weakCompareAndSet and the CAS-retry update/accumulate loops are
// the JVM members the synthetic registrations do not cover.

public fun AtomicBoolean.compareAndSet(expectedValue: Boolean, newValue: Boolean): Boolean =
    compareAndExchange(expectedValue, newValue) == expectedValue

public fun AtomicBoolean.weakCompareAndSet(expect: Boolean, update: Boolean): Boolean =
    compareAndSet(expect, update)

public fun AtomicBoolean.lazySet(newValue: Boolean): Unit = store(newValue)

public fun <T> AtomicReference<T>.compareAndSet(expectedValue: T, newValue: T): Boolean =
    compareAndExchange(expectedValue, newValue) === expectedValue

public fun <T> AtomicReference<T>.weakCompareAndSet(expect: T, update: T): Boolean =
    compareAndSet(expect, update)

public fun <T> AtomicReference<T>.lazySet(newValue: T): Unit = store(newValue)

public fun <T> AtomicReference<T>.getAndUpdate(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun <T> AtomicReference<T>.updateAndGet(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun <T> AtomicReference<T>.getAndAccumulate(x: T, accumulator: (T, T) -> T): T {
    while (true) {
        val old = load()
        val newValue = accumulator(old, x)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun <T> AtomicReference<T>.accumulateAndGet(x: T, accumulator: (T, T) -> T): T {
    while (true) {
        val old = load()
        val newValue = accumulator(old, x)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicInteger.lazySet(newValue: Int): Unit = store(newValue)

public fun AtomicInteger.weakCompareAndSet(expect: Int, update: Int): Boolean =
    compareAndSet(expect, update)

public fun AtomicInteger.getAndAccumulate(x: Int, accumulator: (Int, Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = accumulator(old, x)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicInteger.accumulateAndGet(x: Int, accumulator: (Int, Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = accumulator(old, x)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicLong.lazySet(newValue: Long): Unit = store(newValue)

public fun AtomicLong.weakCompareAndSet(expect: Long, update: Long): Boolean =
    compareAndSet(expect, update)

public fun AtomicLong.getAndUpdate(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicLong.updateAndGet(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicLong.getAndAccumulate(x: Long, accumulator: (Long, Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = accumulator(old, x)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicLong.accumulateAndGet(x: Long, accumulator: (Long, Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = accumulator(old, x)
        if (compareAndSet(old, newValue)) return newValue
    }
}

// AtomicReferenceArray keeps its runtime-backed `*At` member cores (the
// `kk_atomic_ref_array_*` exports use the `At` convention directly); these
// are the JVM-named aliases and CAS-retry loops on top of them. The int/long
// array classes define their members in their own source files because their
// runtime bridges use a different naming convention. The registered element
// type renders nullable (slots may hold null), so the aliased surface takes
// `T?` through every boundary.

public fun <T> AtomicReferenceArray<T>.getAndSet(index: Int, newValue: T?): T? =
    exchangeAt(index, newValue)

public fun <T> AtomicReferenceArray<T>.compareAndSet(index: Int, expect: T?, update: T?): Boolean =
    compareAndSetAt(index, expect, update)

public fun <T> AtomicReferenceArray<T>.weakCompareAndSet(index: Int, expect: T?, update: T?): Boolean =
    compareAndSet(index, expect, update)

public fun <T> AtomicReferenceArray<T>.lazySet(index: Int, newValue: T?): Unit = storeAt(index, newValue)

public fun <T> AtomicReferenceArray<T>.length(): Int = size

public fun <T> AtomicReferenceArray<T>.getAndUpdate(index: Int, transform: (T?) -> T?): T? {
    while (true) {
        val old: T? = loadAt(index)
        val newValue: T? = transform(old)
        if (compareAndSetAt(index, old, newValue)) return old
    }
}

public fun <T> AtomicReferenceArray<T>.updateAndGet(index: Int, transform: (T?) -> T?): T? {
    while (true) {
        val old: T? = loadAt(index)
        val newValue: T? = transform(old)
        if (compareAndSetAt(index, old, newValue)) return newValue
    }
}

public fun <T> AtomicReferenceArray<T>.getAndAccumulate(index: Int, x: T?, accumulator: (T?, T?) -> T?): T? {
    while (true) {
        val old: T? = loadAt(index)
        val newValue: T? = accumulator(old, x)
        if (compareAndSetAt(index, old, newValue)) return old
    }
}

public fun <T> AtomicReferenceArray<T>.accumulateAndGet(index: Int, x: T?, accumulator: (T?, T?) -> T?): T? {
    while (true) {
        val old: T? = loadAt(index)
        val newValue: T? = accumulator(old, x)
        if (compareAndSetAt(index, old, newValue)) return newValue
    }
}
