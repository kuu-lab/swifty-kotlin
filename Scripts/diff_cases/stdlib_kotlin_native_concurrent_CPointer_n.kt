// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs require a Kotlin/Native reference target.
import kotlinx.cinterop.COpaquePointer
import kotlin.native.concurrent.callContinuation0
import kotlin.native.concurrent.callContinuation1
import kotlin.native.concurrent.callContinuation2

fun callContinuationSurface(pointer: COpaquePointer) {
    pointer.callContinuation0()
    pointer.callContinuation1<Int>()
    pointer.callContinuation2<Int, String>()
}

fun main() {}
