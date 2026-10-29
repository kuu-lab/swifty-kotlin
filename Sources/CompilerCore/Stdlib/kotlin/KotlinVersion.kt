package kotlin

import kotlin.internal.KsSymbolName

// `__kk_kotlin_version_current` injects the build-time target Kotlin version
// (see Sources/Runtime/RuntimeKotlinVersion.swift) as a packed
// `major shl 16 or minor shl 8 or patch` integer.

@KsSymbolName("__kk_kotlin_version_current")
private external fun currentKotlinVersionNumber(): Int

public class KotlinVersion(
    public val major: Int,
    public val minor: Int,
    public val patch: Int,
) : Comparable<KotlinVersion> {
    public constructor(major: Int, minor: Int) : this(major, minor, 0)

    override fun toString(): String = "$major.$minor.$patch"

    override fun equals(other: Any?): Boolean {
        if (other !is KotlinVersion) return false
        // Explicit re-cast: `is`-checks do not smart-cast in bundled source yet.
        val that = other as KotlinVersion
        return versionOf(major, minor, patch) == versionOf(that.major, that.minor, that.patch)
    }

    override fun hashCode(): Int = versionOf(major, minor, patch)

    override fun compareTo(other: KotlinVersion): Int {
        val left = versionOf(major, minor, patch)
        val right = versionOf(other.major, other.minor, other.patch)
        if (left < right) return -1
        if (left > right) return 1
        return 0
    }

    public fun isAtLeast(major: Int, minor: Int): Boolean =
        versionOf(this.major, this.minor, this.patch) >= versionOf(major, minor, 0)

    public fun isAtLeast(major: Int, minor: Int, patch: Int): Boolean =
        versionOf(this.major, this.minor, this.patch) >= versionOf(major, minor, patch)

    public companion object {
        public const val MAX_COMPONENT_VALUE: Int = 255

        public val CURRENT: KotlinVersion = currentKotlinVersion()
    }
}

private fun versionOf(major: Int, minor: Int, patch: Int): Int =
    major.shl(16) + minor.shl(8) + patch

// Routed through a top-level function: a companion property initializer that
// constructs a class instance directly is not currently supported for bundled
// source (same constraint as Stdlib/kotlin/io/encoding/HexFormat.kt).
private fun currentKotlinVersion(): KotlinVersion {
    val packed = currentKotlinVersionNumber()
    return KotlinVersion(
        packed.shr(16) and 0xFF,
        packed.shr(8) and 0xFF,
        packed and 0xFF,
    )
}
