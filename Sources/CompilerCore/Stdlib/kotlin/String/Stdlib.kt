package kotlin

// KSP-891: Kotlin's zero-argument String factory returns the empty string.
public fun String(): String = ""
