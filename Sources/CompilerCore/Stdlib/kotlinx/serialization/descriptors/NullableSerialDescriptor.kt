/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */
package kotlinx.serialization.descriptors

import kotlinx.serialization.*
import kotlinx.serialization.internal.SerialDescriptorForNullable

@OptIn(ExperimentalSerializationApi::class)
public val SerialDescriptor.nullable: SerialDescriptor
    get() {
        if (this.isNullable) return this
        return SerialDescriptorForNullable(this)
    }

@ExperimentalSerializationApi
public val SerialDescriptor.nonNullOriginal: SerialDescriptor
    get() = when (this) {
        is SerialDescriptorForNullable -> original
        else -> this
    }
