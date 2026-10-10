/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)

package kotlinx.serialization.descriptors

import kotlinx.serialization.internal.toStringImpl

/** Gives an existing descriptor a distinct serial name. */
@Suppress("FunctionName")
public fun SerialDescriptor(serialName: String, original: SerialDescriptor): SerialDescriptor {
    require(serialName.isNotBlank()) { "Blank serial names are prohibited" }
    require(serialName != original.serialName) { "The name of the wrapped descriptor ($serialName) cannot be the same as the name of the original descriptor (${original.serialName})" }
    if (original.kind is PrimitiveKind) checkNameIsNotAPrimitive(serialName)
    return WrappedSerialDescriptor(serialName, original)
}

internal class WrappedSerialDescriptor(override val serialName: String, private val original: SerialDescriptor) :
    SerialDescriptor by original {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is WrappedSerialDescriptor) return false
        return serialName == other.serialName && original == other.original
    }

    override fun hashCode(): Int {
        var result = serialName.hashCode()
        result = 31 * result + original.hashCode()
        return result
    }

    override fun toString(): String = toStringImpl()
}
