/*
 * Copyright 2010-2018 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib v2.3.10 <libraries/stdlib/src/kotlin/experimental/bitwiseOperations.kt>.
 */
package kotlin.experimental

@SinceKotlin("1.1")
public inline infix fun Byte.and(other: Byte): Byte = (this.toInt() and other.toInt()).toByte()

@SinceKotlin("1.1")
public inline infix fun Byte.or(other: Byte): Byte = (this.toInt() or other.toInt()).toByte()

@SinceKotlin("1.1")
public inline infix fun Byte.xor(other: Byte): Byte = (this.toInt() xor other.toInt()).toByte()

@SinceKotlin("1.1")
public inline fun Byte.inv(): Byte = this.toInt().inv().toByte()

@SinceKotlin("1.1")
public inline infix fun Short.and(other: Short): Short = (this.toInt() and other.toInt()).toShort()

@SinceKotlin("1.1")
public inline infix fun Short.or(other: Short): Short = (this.toInt() or other.toInt()).toShort()

@SinceKotlin("1.1")
public inline infix fun Short.xor(other: Short): Short = (this.toInt() xor other.toInt()).toShort()

@SinceKotlin("1.1")
public inline fun Short.inv(): Short = this.toInt().inv().toShort()
