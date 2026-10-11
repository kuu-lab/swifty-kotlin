@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
package kotlinx.atomicfu
import kotlin.concurrent.atomics.*
public class AppleTestAtomicInt(value: Int) {
    private val storage = AtomicInt(value)
    public var value: Int get() = storage.load()
        set(value) { storage.store(value) }
    public fun getAndIncrement(): Int = storage.fetchAndIncrement()
    public fun getAndAdd(delta: Int): Int = storage.fetchAndAdd(delta)
}
public fun atomic(value: Int): AppleTestAtomicInt = AppleTestAtomicInt(value)
