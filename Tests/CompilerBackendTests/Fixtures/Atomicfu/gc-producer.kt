package lifetime.producer
import kotlinx.atomicfu.*
import kotlin.native.runtime.GC
private class Payload(val id: Int)
public class LifetimeOwner {
    private val first = Payload(41)
    private val ref = atomic<Payload?>(first)
    private val array = atomicArrayOfNulls<Payload>(1)
    init { array[0].value = first }
    public fun collectAndCheck(): Boolean {
        GC.collect()
        return ref.value === first && array[0].value === first
    }
    public fun dropAndCheck(): Boolean {
        ref.value = null
        array[0].value = null
        GC.collect()
        return ref.value == null && array[0].value == null
    }
}
