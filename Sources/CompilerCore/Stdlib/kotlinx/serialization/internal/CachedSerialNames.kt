/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */
package kotlinx.serialization.internal

import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*

@OptIn(ExperimentalSerializationApi::class)
internal fun SerialDescriptor.cachedSerialNames(): Set<String> {
    if (this is CachedNames) return serialNames
    val result = HashSet<String>(elementsCount)
    for (i in 0 until elementsCount) {
        result += getElementName(i)
    }
    return result
}
