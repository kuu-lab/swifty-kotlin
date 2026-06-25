package golden.sema

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.Pinned
import kotlinx.cinterop.pin

@ExperimentalForeignApi
fun testPin(obj: Any): Any {
    val pinned: Pinned<Any> = obj.pin()
    val retrieved: Any = pinned.get()
    pinned.unpin()
    return retrieved
}
