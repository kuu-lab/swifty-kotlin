package io.bytestring.shape.producer

import kotlinx.io.bytestring.ByteString

/** Exposes the exact generic supertype and companion type across a user KLIB boundary. */
fun asComparable(value: ByteString): Comparable<ByteString> = value

fun byteStringCompanion(): ByteString.Companion = ByteString.Companion
