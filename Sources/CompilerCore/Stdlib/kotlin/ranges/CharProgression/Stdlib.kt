/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

// KUU-521: Adopt the existing runtime progression handle as a bundled Kotlin
// nominal. Members and factories retain their existing bridges until the
// remaining RangeProgression migration can follow KUU-519.
public open class CharProgression internal constructor(
    start: Char,
    endInclusive: Char,
    step: Int,
) : Iterable<Char> {
    public companion object {}
}
