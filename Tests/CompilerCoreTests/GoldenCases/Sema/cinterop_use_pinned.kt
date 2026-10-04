package golden.sema

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.Pinned
import kotlinx.cinterop.usePinned

@ExperimentalForeignApi
fun testUsePinned(obj: Any): Any {
    return obj.usePinned { pinned: Pinned<Any> ->
        pinned.get()
    }
}
