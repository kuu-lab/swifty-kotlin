/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/Blob.kt>.
 * Receiver members remain owned by their follow-up migration tasks.
 */

package kotlin.native

@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
public final class ImmutableBlob private constructor()

@Suppress("DEPRECATION_ERROR")
@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
public external fun immutableBlobOf(vararg elements: Short): ImmutableBlob
