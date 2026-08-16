/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/Char.kt>.
 */
package kotlin

import kotlin.text.__charFromCode

/**
 * Creates a Char with the specified [code], or throws an exception if the [code] is out of
 * the valid Char code range 0..0xFFFF.
 */
public inline fun Char(code: Int): Char {
    if (code < 0 || code > 0xFFFF) {
        throw IllegalArgumentException("Invalid Char code: $code")
    }
    return __charFromCode(code)
}

/**
 * Creates a Char with the specified [code].
 */
public inline fun Char(code: UShort): Char = __charFromCode(code.toInt())
