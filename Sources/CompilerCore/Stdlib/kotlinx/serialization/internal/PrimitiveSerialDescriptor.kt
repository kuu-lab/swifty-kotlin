/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)

package kotlinx.serialization.internal

import kotlinx.serialization.descriptors.*

internal class PrimitiveSerialDescriptor(
    override val serialName: String,
    override val kind: PrimitiveKind
) : SerialDescriptor {
    override val elementsCount: Int get() = 0
    override fun getElementName(index: Int): String = error()
    override fun getElementIndex(name: String): Int = error()
    override fun isElementOptional(index: Int): Boolean = error()
    override fun getElementDescriptor(index: Int): SerialDescriptor = error()
    override fun getElementAnnotations(index: Int): List<Annotation> = error()
    override fun toString(): String = "PrimitiveDescriptor($serialName)"
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is PrimitiveSerialDescriptor) return false
        if (serialName == other.serialName && kind == other.kind) return true
        return false
    }
    override fun hashCode() = serialName.hashCode() + 31 * kind.hashCode()
    private fun error(): Nothing = throw IllegalStateException("Primitive descriptor $serialName does not have elements")
}
