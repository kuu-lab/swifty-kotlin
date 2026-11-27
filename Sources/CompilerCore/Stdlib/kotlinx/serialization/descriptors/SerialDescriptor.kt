/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization.descriptors

import kotlinx.serialization.*

@SubclassOptInRequired(SealedSerializationApi::class)
public interface SerialDescriptor {
    public val serialName: String

    public val kind: SerialKind

    public val isNullable: Boolean get() = false

    public val isInline: Boolean get() = false

    public val elementsCount: Int

    public val annotations: List<Annotation> get() = emptyList()

    public fun getElementName(index: Int): String

    public fun getElementIndex(name: String): Int

    public fun getElementAnnotations(index: Int): List<Annotation>

    public fun getElementDescriptor(index: Int): SerialDescriptor

    public fun isElementOptional(index: Int): Boolean
}

public val SerialDescriptor.elementDescriptors: Iterable<SerialDescriptor>
    get() = Iterable {
        object : Iterator<SerialDescriptor> {
            private var elementsLeft = elementsCount
            override fun hasNext(): Boolean = elementsLeft > 0

            override fun next(): SerialDescriptor {
                return getElementDescriptor(elementsCount - (elementsLeft--))
            }
        }
    }

public val SerialDescriptor.elementNames: Iterable<String>
    get() = Iterable {
        object : Iterator<String> {
            private var elementsLeft = elementsCount
            override fun hasNext(): Boolean = elementsLeft > 0

            override fun next(): String {
                return getElementName(elementsCount - (elementsLeft--))
            }
        }
    }
