package golden.sema

import kotlinx.cinterop.COpaquePointer
import kotlin.native.concurrent.callContinuation0
import kotlin.native.concurrent.callContinuation1
import kotlin.native.concurrent.callContinuation2

fun testCallContinuation(pointer: COpaquePointer) {
    pointer.callContinuation0()
    pointer.callContinuation1<Int>()
    pointer.callContinuation2<Int, String>()
}
