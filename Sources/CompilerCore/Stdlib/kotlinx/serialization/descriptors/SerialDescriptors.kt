/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */
@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)

package kotlinx.serialization.descriptors

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.InternalSerializationApi
import kotlinx.serialization.internal.CachedNames
import kotlinx.serialization.internal.toStringImpl

public fun buildClassSerialDescriptor(
    serialName: String,
    vararg typeParameters: SerialDescriptor,
    builderAction: ClassSerialDescriptorBuilder.() -> Unit = {}
): SerialDescriptor {
    require(serialName.isNotBlank()) { "Blank serial names are prohibited" }
    val sdBuilder = ClassSerialDescriptorBuilder(serialName)
    sdBuilder.builderAction()
    return SerialDescriptorImpl(
        serialName,
        StructureKind.CLASS,
        sdBuilder.elementNames.size,
        typeParameters.toList(),
        sdBuilder
    )
}

@InternalSerializationApi
public fun buildSerialDescriptor(
    serialName: String,
    kind: SerialKind,
    vararg typeParameters: SerialDescriptor,
    builder: ClassSerialDescriptorBuilder.() -> Unit = {}
): SerialDescriptor {
    require(serialName.isNotBlank()) { "Blank serial names are prohibited" }
    require(kind != StructureKind.CLASS) { "For StructureKind.CLASS please use 'buildClassSerialDescriptor' instead" }
    val sdBuilder = ClassSerialDescriptorBuilder(serialName)
    sdBuilder.builder()
    return SerialDescriptorImpl(serialName, kind, sdBuilder.elementNames.size, typeParameters.toList(), sdBuilder)
}

public class ClassSerialDescriptorBuilder internal constructor(
    public val serialName: String
) {

    /**
     * Indicates that serializer associated with the current serial descriptor
     * support nullable types, meaning that it should declare nullable type
     * in its [KSerializer] type parameter and handle nulls during encoding and decoding.
     */
    @ExperimentalSerializationApi
    @Deprecated("isNullable inside buildSerialDescriptor is deprecated. Please use SerialDescriptor.nullable extension on a builder result.", level = DeprecationLevel.ERROR)
    public var isNullable: Boolean = false

    /**
     * [Serial][SerialInfo] annotations on a target type.
     */
    @ExperimentalSerializationApi
    public var annotations: List<Annotation> = emptyList()

    internal val elementNames: MutableList<String> = ArrayList()
    private val uniqueNames: MutableSet<String> = HashSet()
    internal val elementDescriptors: MutableList<SerialDescriptor> = ArrayList()
    internal val elementAnnotations: MutableList<List<Annotation>> = ArrayList()
    internal val elementOptionality: MutableList<Boolean> = ArrayList()

    /**
     * Add an element with a given [name][elementName], [descriptor],
     * type annotations and optionality the resulting descriptor.
     *
     * Example of usage:
     * ```
     * class Data(
     *     val intField: Int? = null, // Optional, has default value
     *     @ProtoNumber(1) val longField: Long
     * )
     *
     * // Corresponding descriptor
     * SerialDescriptor("package.Data") {
     *     element<Int?>("intField", isOptional = true)
     *     element<Long>("longField", annotations = listOf(protoIdAnnotationInstance))
     * }
     * ```
     */
    public fun element(
        elementName: String,
        descriptor: SerialDescriptor,
        annotations: List<Annotation> = emptyList(),
        isOptional: Boolean = false
    ) {
        require(uniqueNames.add(elementName)) { "Element with name '$elementName' is already registered in $serialName" }
        elementNames += elementName
        elementDescriptors += descriptor
        elementAnnotations += annotations
        elementOptionality += isOptional
    }
}

internal class SerialDescriptorImpl(
    override val serialName: String,
    override val kind: SerialKind,
    override val elementsCount: Int,
    typeParameters: List<SerialDescriptor>,
    builder: ClassSerialDescriptorBuilder
) : SerialDescriptor, CachedNames {

    @OptIn(ExperimentalSerializationApi::class)
    override val annotations: List<Annotation> = builder.annotations
    override val serialNames: Set<String> = builder.elementNames.toHashSet()

    private val elementNames: Array<String> = builder.elementNames.toTypedArray()
    private val elementDescriptors: Array<SerialDescriptor> = builder.elementDescriptors.compactArray()
    private val elementAnnotations: Array<List<Annotation>> = builder.elementAnnotations.toTypedArray()
    private val elementOptionality: BooleanArray = builder.elementOptionality.toBooleanArray()
    private val name2Index: Map<String, Int> = elementNames.withIndex().map { it.value to it.index }.toMap()
    private val typeParametersDescriptors: Array<SerialDescriptor> = typeParameters.compactArray()
    private val _hashCode: Int by lazy { hashCodeImpl(typeParametersDescriptors) }

    override fun getElementName(index: Int): String = elementNames[index]
    override fun getElementIndex(name: String): Int = name2Index[name] ?: -3
    override fun getElementAnnotations(index: Int): List<Annotation> = elementAnnotations[index]
    override fun getElementDescriptor(index: Int): SerialDescriptor = elementDescriptors[index]
    override fun isElementOptional(index: Int): Boolean = elementOptionality[index]

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SerialDescriptorImpl) return false
        if (serialName != other.serialName) return false
        if (!typeParametersDescriptors.contentEquals(other.typeParametersDescriptors)) return false
        if (elementsCount != other.elementsCount) return false
        for (index in 0 until elementsCount) {
            if (getElementDescriptor(index).serialName != other.getElementDescriptor(index).serialName) return false
            if (getElementDescriptor(index).kind != other.getElementDescriptor(index).kind) return false
        }
        return true
    }

    override fun hashCode(): Int = _hashCode

    override fun toString(): String = toStringImpl()
}

private fun List<SerialDescriptor>.compactArray(): Array<SerialDescriptor> = toTypedArray()

private fun SerialDescriptor.hashCodeImpl(typeParams: Array<SerialDescriptor>): Int {
    var result = serialName.hashCode()
    result = 31 * result + typeParams.contentHashCode()
    var namesHash = 1
    for (index in 0 until elementsCount) {
        namesHash = 31 * namesHash + getElementDescriptor(index).serialName.hashCode()
    }
    var kindHash = 1
    for (index in 0 until elementsCount) {
        kindHash = 31 * kindHash + getElementDescriptor(index).kind.hashCode()
    }
    result = 31 * result + namesHash
    result = 31 * result + kindHash
    return result
}
