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

@OptIn(ExperimentalStdlibApi::class)
public fun ByteString.toHexString(format: HexFormat = defaultByteStringHexFormat()): String {
    return getBackingArrayReference().toHexString(0, getBackingArrayReference().size, format)
}

@OptIn(ExperimentalStdlibApi::class)
public fun ByteString.toHexString(
    startIndex: Int = 0,
    endIndex: Int = size,
    format: HexFormat = defaultByteStringHexFormat()
): String {
    return getBackingArrayReference().toHexString(startIndex, endIndex, format)
}

@OptIn(ExperimentalStdlibApi::class)
public fun String.hexToByteString(format: HexFormat = defaultByteStringHexFormat()): ByteString {
    return ByteString.wrap(hexToByteArray(format))
}
