/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Adapted from kotlinx-io 0.9.1 bytestring/common/src/Hex.kt.
 */
package kotlinx.io.bytestring

// `HexFormat.Default` cannot sit in a default parameter value for the same
// reason as in kotlin/text/HexFormat.kt (a default value that reads a companion
// property or constructs an instance emits an undefined symbol at link time), so
// the defaults below route through a plain private function instead. The
// kotlin.text hex primitives called here are still `@ExperimentalStdlibApi` in
// the bundled stdlib, hence the local `@OptIn`; the functions themselves are
// stable in kotlinx-io and must not propagate an opt-in requirement to callers.
private fun defaultByteStringHexFormat(): HexFormat = HexFormat.Default

/**
 * Formats bytes in this byte string using the specified [format].
 *
 * Note that only [HexFormat.upperCase] and [HexFormat.BytesHexFormat] affect formatting.
 *
 * @param format the [HexFormat] to use for formatting, [HexFormat.Default] by default.
 *
 * @throws IllegalArgumentException if the result length is more than [String] maximum capacity.
 */
@OptIn(ExperimentalStdlibApi::class)
public fun ByteString.toHexString(format: HexFormat = defaultByteStringHexFormat()): String {
    return getBackingArrayReference().toHexString(0, getBackingArrayReference().size, format)
}

/**
 * Formats bytes in this byte string using the specified [HexFormat].
 *
 * Note that only [HexFormat.upperCase] and [HexFormat.BytesHexFormat] affect formatting.
 *
 * @param startIndex the beginning (inclusive) of the subrange to format, 0 by default.
 * @param endIndex the end (exclusive) of the subrange to format, size of this byte string by default.
 * @param format the [HexFormat] to use for formatting, [HexFormat.Default] by default.
 *
 * @throws IndexOutOfBoundsException when [startIndex] or [endIndex] is out of range of this byte string indices.
 * @throws IllegalArgumentException when `startIndex > endIndex`.
 * @throws IllegalArgumentException if the result length is more than [String] maximum capacity.
 */
@OptIn(ExperimentalStdlibApi::class)
public fun ByteString.toHexString(
    startIndex: Int = 0,
    endIndex: Int = size,
    format: HexFormat = defaultByteStringHexFormat()
): String {
    return getBackingArrayReference().toHexString(startIndex, endIndex, format)
}

/**
 * Parses bytes from this string using the specified [HexFormat].
 *
 * Note that only [HexFormat.BytesHexFormat] affects parsing,
 * and parsing is performed in case-insensitive manner.
 * Also, any of the char sequences CRLF, LF and CR is considered a valid line separator.
 *
 * @param format the [HexFormat] to use for parsing, [HexFormat.Default] by default.
 *
 * @throws IllegalArgumentException if this string does not comply with the specified [format].
 */
@OptIn(ExperimentalStdlibApi::class)
public fun String.hexToByteString(format: HexFormat = defaultByteStringHexFormat()): ByteString {
    return ByteString.wrap(hexToByteArray(format))
}
