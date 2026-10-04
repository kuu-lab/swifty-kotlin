@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

package golden.sema

import kotlin.concurrent.atomics.AtomicArray
import kotlin.concurrent.atomics.AtomicBoolean
import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.AtomicIntArray
import kotlin.concurrent.atomics.AtomicLong
import kotlin.concurrent.atomics.AtomicLongArray
import kotlin.concurrent.atomics.AtomicNativePtr
import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.atomicArrayOfNulls

fun atomicIntType(): AtomicInt? = null
fun atomicLongType(): AtomicLong? = null
fun atomicBooleanType(): AtomicBoolean? = null
fun atomicReferenceType(value: AtomicReference<String>): AtomicReference<String> = value
fun atomicArrayType(value: AtomicArray<String?>): AtomicArray<String?> = value
fun atomicNativePtrType(): AtomicNativePtr? = null
fun atomicIntArrayType(): AtomicIntArray? = null
fun atomicLongArrayType(): AtomicLongArray? = null

fun atomicBooleanFactory(): AtomicBoolean = AtomicBoolean(true)
fun atomicIntFactory(): AtomicInt = AtomicInt(1)
fun atomicLongFactory(): AtomicLong = AtomicLong(1L)
fun atomicIntArrayFactory(): AtomicIntArray = AtomicIntArray(2) { it }
fun atomicLongArrayFactory(): AtomicLongArray = AtomicLongArray(2) { it.toLong() }
fun atomicArrayFactory(): AtomicArray<String> = AtomicArray(2) { it.toString() }
fun atomicArrayOfNullsFactory(): AtomicArray<String?> = atomicArrayOfNulls(2)
