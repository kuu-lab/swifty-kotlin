@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)
import kotlinx.atomicfu.*
import kotlinx.atomicfu.locks.*
import kotlin.native.runtime.GC

class Payload(val id: Int)
fun main() {
    val first = Payload(7)
    val ref = atomic<Payload?>(first)
    val array = atomicArrayOfNulls<Payload>(2)
    array[0].value = first
    array[1].value = first
    GC.collect()
    println(ref.value === first)
    println(array[0].value === array[1].value)
    ref.value = null
    array[0].value = null
    GC.collect()
    println(ref.value == null)
    println(array[1].value!!.id)
    val lock = SynchronizedObject()
    println(synchronized(lock) { synchronized(lock) { 9 } })
    val own = ParkingSupport.currentThreadHandle()
    GC.collect()
    println(own === ParkingSupport.currentThreadHandle())
}
