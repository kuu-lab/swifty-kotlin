/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */
package kotlinx.serialization.descriptors

import kotlinx.serialization.*
import kotlinx.serialization.internal.SerialDescriptorForNullable

/**
 * Returns new serial descriptor for the same type with [isNullable][SerialDescriptor.isNullable]
 * property set to `true`.
 */
@OptIn(ExperimentalSerializationApi::class)
public val SerialDescriptor.nullable: SerialDescriptor
    get() {
        if (this.isNullable) return this
        return SerialDescriptorForNullable(this)
    }

/**
 * Returns non-nullable serial descriptor for the type if this descriptor has been auto-generated (plugin
 * generated descriptors) or created with `.nullable` extension on a descriptor or serializer.
 *
 * Otherwise, returns `this`.
 *
 * It may return a nullable descriptor
 * if `this` descriptor has been created manually as nullable by directly implementing SerialDescriptor interface.
 *
 * @see SerialDescriptor.nullable
 * @see KSerializer.nullable
 */
@ExperimentalSerializationApi
public val SerialDescriptor.nonNullOriginal: SerialDescriptor
    get() = when (this) {
        is SerialDescriptorForNullable -> original
        else -> this
    }
