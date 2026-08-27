/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib core/builtins/src/kotlin/Unit.kt.
 */

package kotlin

// KSP-765: migrate the nominal kotlin.Unit singleton to bundled Kotlin source.
// Unit's value representation remains the compiler's builtin unit type; this
// declaration supplies the source-backed public singleton symbol.
public object Unit {
    override fun toString(): String = "kotlin.Unit"
}
