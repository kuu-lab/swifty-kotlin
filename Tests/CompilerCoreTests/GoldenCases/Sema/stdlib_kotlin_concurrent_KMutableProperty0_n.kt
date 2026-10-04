@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.concurrent.atomicGetField
import kotlin.concurrent.atomicSetField
import kotlin.concurrent.compareAndExchangeField
import kotlin.concurrent.compareAndSetField
import kotlin.concurrent.getAndAddField
import kotlin.concurrent.getAndSetField
import kotlin.reflect.KMutableProperty0

fun read(property: KMutableProperty0<Int>): Int = property.atomicGetField()
fun write(property: KMutableProperty0<Int>, value: Int): Unit = property.atomicSetField(value)
fun compareAndSet(property: KMutableProperty0<Int>, expected: Int, value: Int): Boolean =
    property.compareAndSetField(expected, value)
fun compareAndExchange(property: KMutableProperty0<Int>, expected: Int, value: Int): Int =
    property.compareAndExchangeField(expected, value)
fun getAndSet(property: KMutableProperty0<Int>, value: Int): Int = property.getAndSetField(value)
fun getAndAddByte(property: KMutableProperty0<Byte>, delta: Byte): Byte = property.getAndAddField(delta)
fun getAndAddShort(property: KMutableProperty0<Short>, delta: Short): Short = property.getAndAddField(delta)
fun getAndAddInt(property: KMutableProperty0<Int>, delta: Int): Int = property.getAndAddField(delta)
fun getAndAddLong(property: KMutableProperty0<Long>, delta: Long): Long = property.getAndAddField(delta)
