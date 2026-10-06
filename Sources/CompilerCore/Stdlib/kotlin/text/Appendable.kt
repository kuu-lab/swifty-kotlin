/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib common Appendable declarations.
 */

package kotlin.text

/** The append contract shared by StringBuilder and other mutable character sinks. */
public interface Appendable {
    public fun append(value: Char): Appendable

    public fun append(value: CharSequence?): Appendable

    public fun append(value: CharSequence?, startIndex: Int, endIndex: Int): Appendable
}

/** Appends a line feed character (`\n`) to this Appendable. */
@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(): Appendable = append('\n')

/** Appends a nullable character sequence and a line feed character (`\n`). */
@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(value: CharSequence?): Appendable = append(value).appendLine()

/** Appends a character and a line feed character (`\n`). */
@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(value: Char): Appendable = append(value).appendLine()
