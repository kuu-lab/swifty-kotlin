/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib common Appendable declarations.
 */

package kotlin.text

public interface Appendable {
    public fun append(value: Char): Appendable

    public fun append(value: CharSequence?): Appendable

    public fun append(value: CharSequence?, startIndex: Int, endIndex: Int): Appendable
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(): Appendable = append('\n')

@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(value: CharSequence?): Appendable = append(value).appendLine()

@SinceKotlin("1.4")
@IgnorableReturnValue
public inline fun Appendable.appendLine(value: Char): Appendable = append(value).appendLine()
