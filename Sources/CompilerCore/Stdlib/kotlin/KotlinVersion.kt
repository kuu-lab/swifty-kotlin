/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/KotlinVersion.kt.
 */

package kotlin

import kotlin.internal.KsSymbolName

/**
 * Returns the Kotlin version this compiler build targets, packed as
 * `major shl 16 + minor shl 8 + patch`. The value is a build-time constant of
 * the Swift runtime; nothing else about `KotlinVersion` needs runtime support.
 */
@KsSymbolName("__kk_kotlin_version_current")
private external fun __kkKotlinVersionCurrent(): Int

/**
 * Represents a version of the Kotlin standard library.
 */
public class KotlinVersion(
    public val major: Int,
    public val minor: Int,
    public val patch: Int,
) : Comparable<KotlinVersion> {
    internal val versionNumber: Int = versionOf(major, minor, patch)

    public constructor(major: Int, minor: Int) : this(major, minor, 0)

    private fun versionOf(major: Int, minor: Int, patch: Int): Int {
        require(
            major in 0..MAX_COMPONENT_VALUE &&
                minor in 0..MAX_COMPONENT_VALUE &&
                patch in 0..MAX_COMPONENT_VALUE
        ) {
            "Version components are out of range: $major.$minor.$patch"
        }
        return major.shl(16) + minor.shl(8) + patch
    }

    public override fun toString(): String = "$major.$minor.$patch"

    public override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is KotlinVersion) return false
        // Explicit cast: smart cast after `!is` + early return is a known gap
        // (TODO.md DEBT-DIFF-007).
        val otherVersion = other as KotlinVersion
        return versionNumber == otherVersion.versionNumber
    }

    public override fun hashCode(): Int = versionNumber

    public override fun compareTo(other: KotlinVersion): Int = versionNumber - other.versionNumber

    /**
     * Returns `true` if this version is not less than the version specified
     * with the provided [major] and [minor] components.
     */
    public fun isAtLeast(major: Int, minor: Int): Boolean =
        this.major > major || (this.major == major && this.minor >= minor)

    /**
     * Returns `true` if this version is not less than the version specified
     * with the provided [major], [minor] and [patch] components.
     */
    public fun isAtLeast(major: Int, minor: Int, patch: Int): Boolean =
        this.major > major ||
            (
                this.major == major &&
                    (this.minor > minor || (this.minor == minor && this.patch >= patch))
            )

    public companion object {
        /** Maximum value a version component can have, a constant value 255. */
        public const val MAX_COMPONENT_VALUE: Int = 255

        /** Returns the current version of the Kotlin standard library. */
        public val CURRENT: KotlinVersion = fromVersionNumber(__kkKotlinVersionCurrent())

        private fun fromVersionNumber(versionNumber: Int): KotlinVersion =
            KotlinVersion(
                versionNumber.shr(16) and 0xFF,
                versionNumber.shr(8) and 0xFF,
                versionNumber and 0xFF
            )
    }
}
