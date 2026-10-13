/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package kotlinx.serialization.descriptors

import kotlinx.serialization.internal.PrimitiveSerialDescriptor as PrimitiveDescriptor

/** Creates a zero-element descriptor for a custom primitive serializer. */
@Suppress("FunctionName")
public fun PrimitiveSerialDescriptor(serialName: String, kind: PrimitiveKind): SerialDescriptor {
    require(serialName.isNotBlank()) { "Blank serial names are prohibited" }
    checkNameIsNotAPrimitive(serialName)
    return PrimitiveDescriptor(serialName, kind)
}

// The native 1.10.0 builtin registry also reserves arrays, unsigned types,
// Unit, Nothing, Duration, Instant and Uuid, independently of the requested kind.
internal fun checkNameIsNotAPrimitive(serialName: String) {
    val serializerName: String? = when (serialName) {
        "kotlin.String" -> "StringSerializer"
        "kotlin.Char" -> "CharSerializer"
        "kotlin.CharArray" -> "CharArraySerializer"
        "kotlin.Double" -> "DoubleSerializer"
        "kotlin.DoubleArray" -> "DoubleArraySerializer"
        "kotlin.Float" -> "FloatSerializer"
        "kotlin.FloatArray" -> "FloatArraySerializer"
        "kotlin.Long" -> "LongSerializer"
        "kotlin.LongArray" -> "LongArraySerializer"
        "kotlin.ULong" -> "ULongSerializer"
        "kotlin.ULongArray" -> "ULongArraySerializer"
        "kotlin.Int" -> "IntSerializer"
        "kotlin.IntArray" -> "IntArraySerializer"
        "kotlin.UInt" -> "UIntSerializer"
        "kotlin.UIntArray" -> "UIntArraySerializer"
        "kotlin.Short" -> "ShortSerializer"
        "kotlin.ShortArray" -> "ShortArraySerializer"
        "kotlin.UShort" -> "UShortSerializer"
        "kotlin.UShortArray" -> "UShortArraySerializer"
        "kotlin.Byte" -> "ByteSerializer"
        "kotlin.ByteArray" -> "ByteArraySerializer"
        "kotlin.UByte" -> "UByteSerializer"
        "kotlin.UByteArray" -> "UByteArraySerializer"
        "kotlin.Boolean" -> "BooleanSerializer"
        "kotlin.BooleanArray" -> "BooleanArraySerializer"
        "kotlin.Unit" -> "UnitSerializer"
        "kotlin.Nothing" -> "NothingSerializer"
        "kotlin.time.Duration" -> "DurationSerializer"
        "kotlin.time.Instant" -> "InstantSerializer"
        "kotlin.uuid.Uuid" -> "UuidSerializer"
        else -> null
    }
    if (serializerName != null) {
        throw IllegalArgumentException("The name of serial descriptor should uniquely identify associated serializer.\nFor serial name $serialName there already exists $serializerName.\nPlease refer to SerialDescriptor documentation for additional information.")
    }
}
