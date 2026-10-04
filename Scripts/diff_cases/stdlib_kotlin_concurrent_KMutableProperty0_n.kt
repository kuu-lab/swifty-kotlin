// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent KMutableProperty0 field APIs are
// Kotlin/Native-only and are unavailable in the JVM kotlinc reference environment.
// KSP-1084: source-backed receiverless mutable property field operations.
// The upstream declarations are Kotlin/Native-only; the local implementation
// preserves their sequential get/set and arithmetic behavior.
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlin.concurrent.atomicGetField
import kotlin.concurrent.atomicSetField
import kotlin.concurrent.compareAndExchangeField
import kotlin.concurrent.compareAndSetField
import kotlin.concurrent.getAndAddField
import kotlin.concurrent.getAndSetField
import kotlin.reflect.KMutableProperty0

var refInt: Int = 10
var refLong: Long = 20L
var refShort: Short = 30
var refByte: Byte = 40

fun main() {
    val intProperty: KMutableProperty0<Int> = ::refInt
    println(intProperty.atomicGetField())
    intProperty.atomicSetField(11)
    println(intProperty.getAndSetField(12))
    println(intProperty.compareAndSetField(12, 13))
    println(intProperty.compareAndExchangeField(99, 14))
    println(intProperty.compareAndExchangeField(13, 14))
    println(intProperty.getAndAddField(2))
    println(refInt)

    val longProperty: KMutableProperty0<Long> = ::refLong
    println(longProperty.getAndAddField(3L))
    println(refLong)

    val shortProperty: KMutableProperty0<Short> = ::refShort
    println(shortProperty.getAndAddField(4))
    println(refShort)

    val byteProperty: KMutableProperty0<Byte> = ::refByte
    println(byteProperty.getAndAddField(5))
    println(refByte)
}
