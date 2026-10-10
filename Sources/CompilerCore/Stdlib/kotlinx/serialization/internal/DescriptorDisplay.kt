/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package kotlinx.serialization.internal

import kotlinx.serialization.descriptors.SerialDescriptor

internal fun SerialDescriptor.toStringImpl(): String = (0 until elementsCount).joinToString(", ", "$serialName(", ")") { i ->
    getElementName(i) + ": " + getElementDescriptor(i).serialName
}
