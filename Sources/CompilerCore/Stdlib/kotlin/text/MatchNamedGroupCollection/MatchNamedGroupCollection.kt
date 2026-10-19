/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib commonMain/kotlin/text/regex/MatchResult.kt.
 */

package kotlin.text

@SinceKotlin("1.1")
public interface MatchNamedGroupCollection : MatchGroupCollection {
    /**
     * @return An instance of [MatchGroup] if the group with the specified [name]
     * was matched or `null` otherwise.
     * @throws IllegalArgumentException if no group with the specified [name] is
     * defined in the regex pattern.
     * @throws UnsupportedOperationException if this collection does not support
     * getting match groups by name.
     */
    public override operator fun get(name: String): MatchGroup?
}
