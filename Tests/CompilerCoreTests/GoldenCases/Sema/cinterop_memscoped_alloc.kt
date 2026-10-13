package golden.sema

import kotlinx.cinterop.memScoped
import kotlinx.cinterop.alloc
import kotlinx.cinterop.IntVar
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.cstr
import kotlinx.cinterop.toKString
import kotlinx.cinterop.nativeHeap
import kotlinx.cinterop.sizeOf
import kotlinx.cinterop.alignOf
import kotlinx.cinterop.ExperimentalForeignApi

@ExperimentalForeignApi
fun roundTrip(): String = memScoped {
    val intVar = alloc<IntVar>()
    intVar.value = 42
    val arr = allocArray<IntVar>(2)
    arr[0].value = 1
    arr[1].value = 2
    val size = sizeOf<IntVar>()
    val align = alignOf<IntVar>()
    val heapVar = nativeHeap.alloc<IntVar>()
    heapVar.value = 7
    nativeHeap.free(heapVar.ptr)
    "answer-${intVar.value}-${arr[0].value}-${arr[1].value}-$size-$align".cstr.toKString()
}
