/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/simd.kt>.
 */

package kotlin.native

public external fun vectorOf(
    x: Float,
    y: Float,
    z: Float,
    w: Float
): kotlinx.cinterop.Vector128

public external fun vectorOf(
    x: Int,
    y: Int,
    z: Int,
    w: Int
): kotlinx.cinterop.Vector128
