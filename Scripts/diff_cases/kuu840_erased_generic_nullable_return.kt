@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicReference

// Exercise a function-generic return after it crosses an erased AtomicReference
// boundary, then pass the same value through an unchecked `as T` cast.
fun <T> loadErased(reference: AtomicReference<T>): T = reference.load() as T

fun <T> castErased(value: Any?): T = value as T

fun <T> castLoadedErased(reference: AtomicReference<T>): T = reference.load() as T

fun main() {
    val intReference = AtomicReference<Int?>(null)
    val booleanReference = AtomicReference<Boolean?>(null)
    val doubleReference = AtomicReference<Double?>(null)
    val charReference = AtomicReference<Char?>(null)
    val longReference = AtomicReference<Long?>(null)
    val stringReference = AtomicReference<String?>(null)

    println(loadErased(intReference))
    println(loadErased(booleanReference))
    println(loadErased(doubleReference))
    println(loadErased(charReference))
    println(loadErased(longReference))
    println(loadErased(stringReference))

    println(castLoadedErased(intReference))
    println(castLoadedErased(booleanReference))
    println(castLoadedErased(doubleReference))
    println(castLoadedErased(charReference))
    println(castLoadedErased(longReference))
    println(castLoadedErased(stringReference))

    println(castErased<Int?>(intReference.load()))
    println(castErased<Boolean?>(booleanReference.load()))
    println(castErased<Double?>(doubleReference.load()))
    println(castErased<Char?>(charReference.load()))
    println(castErased<Long?>(longReference.load()))
    println(castErased<String?>(stringReference.load()))
}
