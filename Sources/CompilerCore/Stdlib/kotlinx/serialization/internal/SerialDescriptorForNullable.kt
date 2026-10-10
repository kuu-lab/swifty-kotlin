/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */
@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)
package kotlinx.serialization.internal

import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*

internal class SerialDescriptorForNullable(
    internal val original: SerialDescriptor
) : SerialDescriptor by original, CachedNames {

    override val serialName: String = original.serialName + "?"
    override val serialNames: Set<String> = original.cachedSerialNames()
    override val isNullable: Boolean
        get() = true

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SerialDescriptorForNullable) return false
        if (original != other.original) return false
        return true
    }

    override fun toString(): String {
        return "$original?"
    }

    override fun hashCode(): Int {
        return original.hashCode() * 31
    }
}
