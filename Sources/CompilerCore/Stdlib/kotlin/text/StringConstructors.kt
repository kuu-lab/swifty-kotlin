/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib platform String constructor declarations.
 */

package kotlin

import kotlin.internal.KsSymbolName
import kotlin.text.Charset

// String remains a compiler/runtime nominal shell. These source declarations
// own the public constructor overloads while the byte decoding itself remains
// in the private __kk_* runtime bridges used by StringEncoding.kt. The
// internal List<Int> overloads preserve KSwiftK's ByteArray representation
// without widening the public Kotlin API.
@KsSymbolName("__kk_bytearray_decodeToString")
public external fun String(bytes: ByteArray): String

@KsSymbolName("__kk_bytearray_decodeToString_charset")
public external fun String(bytes: ByteArray, charset: Charset): String

@KsSymbolName("__kk_bytearray_decodeToString")
internal external fun String(bytes: List<Int>): String

@KsSymbolName("__kk_bytearray_decodeToString_charset")
internal external fun String(bytes: List<Int>, charset: Charset): String
