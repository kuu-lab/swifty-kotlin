/*
 * Copyright 2017-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

@file:Suppress("UNCHECKED_CAST")
@file:OptIn(ExperimentalSerializationApi::class, InternalSerializationApi::class)

package kotlinx.serialization

import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.modules.SerializersModule
import kotlin.reflect.KClass
import kotlin.reflect.KFunction
import kotlin.reflect.KParameter
import kotlin.reflect.KProperty1
import kotlin.reflect.full.memberProperties
import kotlin.reflect.full.primaryConstructor

private class SerializableProperty<T : Any>(
    val property: KProperty1<T, *>,
    val isOptional: Boolean
)

/**
 * Runtime fallback used by the native compiler's serialization plugin.
 * The plugin emits the source-compatible `Owner.serializer()` entry point;
 * this serializer uses the reflection metadata already emitted for the class.
 */
internal class ReflectiveClassSerializer<T : Any>(
    private val serializableClass: KClass<T>
) : KSerializer<T> {
    private fun primaryConstructorOrNull(): KFunction<T>? = serializableClass.primaryConstructor

    private fun serializableProperties(): List<SerializableProperty<T>> {
        val propertiesByName = HashMap<String, KProperty1<T, *>>()
        for (candidate in serializableClass.memberProperties) {
            val property = candidate as? KProperty1<T, *> ?: continue
            propertiesByName[property.name] = property
        }
        return primaryConstructorOrNull()?.parameters
            ?.asSequence()
            ?.filter { it.kind == KParameter.Kind.VALUE }
            ?.mapNotNull { parameter ->
                val property = parameter.name?.let(propertiesByName::get) ?: return@mapNotNull null
                if (property.annotations.any { it is Transient }) {
                    null
                } else {
                    SerializableProperty(property, parameter.isOptional)
                }
            }
            ?.toList()
            ?: emptyList()
    }

    override val descriptor: SerialDescriptor
        get() {
            val classSerialName = serializableClass.annotations
                .filterIsInstance<SerialName>()
                .firstOrNull()
                ?.value
                ?: serializableClass.qualifiedName
                ?: serializableClass.simpleName
                ?: "<anonymous>"
            val properties = serializableProperties()
            return buildClassSerialDescriptor(classSerialName) {
                for (serializableProperty in properties) {
                    val property = serializableProperty.property
                    val name = property.serialName()
                    element(
                        name,
                        serializer(property.returnType).descriptor,
                        isOptional = serializableProperty.isOptional
                    )
                }
            }
        }

    override fun serialize(encoder: Encoder, value: T) {
        val properties = serializableProperties()
        val serialDescriptor = descriptor
        val composite = encoder.beginStructure(serialDescriptor)
        for ((index, serializableProperty) in properties.withIndex()) {
            val property = serializableProperty.property
            val propertyValue = property.get(value)
            composite.encodeSerializableElement(
                serialDescriptor,
                index,
                serializer(property.returnType),
                propertyValue
            )
        }
        composite.endStructure(serialDescriptor)
    }

    override fun deserialize(decoder: Decoder): T {
        val properties = serializableProperties()
        val serialDescriptor = descriptor
        val composite = decoder.beginStructure(serialDescriptor)
        val decodedValues = HashMap<String, Any?>()
        while (true) {
            val index = composite.decodeElementIndex(serialDescriptor)
            if (index == -1) break
            if (index < 0 || index >= properties.size) continue
            val property = properties[index].property
            decodedValues[property.name] = composite.decodeSerializableElement(
                serialDescriptor,
                index,
                serializer(property.returnType)
            )
        }
        composite.endStructure(serialDescriptor)

        val targetConstructor = primaryConstructorOrNull()
            ?: throw SerializationException("Class ${serializableClass.qualifiedName} has no primary constructor")
        val constructorArguments = HashMap<KParameter, Any?>()
        val missingFields = ArrayList<String>()
        for (parameter in targetConstructor.parameters) {
            if (parameter.kind != KParameter.Kind.VALUE) continue
            val name = parameter.name ?: continue
            if (decodedValues.containsKey(name)) {
                constructorArguments[parameter] = decodedValues[name]
            } else if (!parameter.isOptional) {
                missingFields += descriptorName(name, properties)
            }
        }
        if (missingFields.isNotEmpty()) {
            throw MissingFieldException(missingFields, serialDescriptor.serialName)
        }
        return targetConstructor.callBy(constructorArguments)
    }

    private fun KProperty1<T, *>.serialName(): String = annotations
        .filterIsInstance<SerialName>()
        .firstOrNull()
        ?.value
        ?: name

    private fun descriptorName(
        propertyName: String,
        properties: List<SerializableProperty<T>>
    ): String {
        for (serializableProperty in properties) {
            val property = serializableProperty.property
            if (property.name == propertyName) return property.serialName()
        }
        return propertyName
    }
}

/** Entry point used by compiler-generated companion `serializer()` functions. */
internal fun serializerForClass(kClass: KClass<*>): KSerializer<Any?> {
    @Suppress("UNCHECKED_CAST")
    return (kClass as KClass<Any>).serializer() as KSerializer<Any?>
}

@Suppress("UNCHECKED_CAST")
internal fun <T : Any> builtinSerializerOrNull(kClass: KClass<T>): KSerializer<T>? {
    val serializer: KSerializer<*> = when (kClass) {
        String::class -> StringSerializer
        Boolean::class -> BooleanSerializer
        Byte::class -> ByteSerializer
        Short::class -> ShortSerializer
        Char::class -> CharSerializer
        Int::class -> IntSerializer
        Long::class -> LongSerializer
        Float::class -> FloatSerializer
        Double::class -> DoubleSerializer
        else -> return null
    }
    return serializer as KSerializer<T>
}

private object StringSerializer : KSerializer<String> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.String", kotlinx.serialization.descriptors.PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
    override fun deserialize(decoder: Decoder): String = decoder.decodeString()
}

private object BooleanSerializer : KSerializer<Boolean> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.Boolean", kotlinx.serialization.descriptors.PrimitiveKind.BOOLEAN)
    override fun serialize(encoder: Encoder, value: Boolean) = encoder.encodeBoolean(value)
    override fun deserialize(decoder: Decoder): Boolean = decoder.decodeBoolean()
}

private object ByteSerializer : KSerializer<Byte> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.Byte", kotlinx.serialization.descriptors.PrimitiveKind.BYTE)
    override fun serialize(encoder: Encoder, value: Byte) = encoder.encodeByte(value)
    override fun deserialize(decoder: Decoder): Byte = decoder.decodeByte()
}

private object ShortSerializer : KSerializer<Short> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.Short", kotlinx.serialization.descriptors.PrimitiveKind.SHORT)
    override fun serialize(encoder: Encoder, value: Short) = encoder.encodeShort(value)
    override fun deserialize(decoder: Decoder): Short = decoder.decodeShort()
}

private object CharSerializer : KSerializer<Char> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.Char", kotlinx.serialization.descriptors.PrimitiveKind.CHAR)
    override fun serialize(encoder: Encoder, value: Char) = encoder.encodeChar(value)
    override fun deserialize(decoder: Decoder): Char = decoder.decodeChar()
}

private object IntSerializer : KSerializer<Int> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.Int", kotlinx.serialization.descriptors.PrimitiveKind.INT)
    override fun serialize(encoder: Encoder, value: Int) = encoder.encodeInt(value)
    override fun deserialize(decoder: Decoder): Int = decoder.decodeInt()
}

private object LongSerializer : KSerializer<Long> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.Long", kotlinx.serialization.descriptors.PrimitiveKind.LONG)
    override fun serialize(encoder: Encoder, value: Long) = encoder.encodeLong(value)
    override fun deserialize(decoder: Decoder): Long = decoder.decodeLong()
}

private object FloatSerializer : KSerializer<Float> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.Float", kotlinx.serialization.descriptors.PrimitiveKind.FLOAT)
    override fun serialize(encoder: Encoder, value: Float) = encoder.encodeFloat(value)
    override fun deserialize(decoder: Decoder): Float = decoder.decodeFloat()
}

private object DoubleSerializer : KSerializer<Double> {
    override val descriptor: SerialDescriptor = primitiveDescriptor("kotlin.Double", kotlinx.serialization.descriptors.PrimitiveKind.DOUBLE)
    override fun serialize(encoder: Encoder, value: Double) = encoder.encodeDouble(value)
    override fun deserialize(decoder: Decoder): Double = decoder.decodeDouble()
}

private fun primitiveDescriptor(
    name: String,
    kind: kotlinx.serialization.descriptors.PrimitiveKind
): SerialDescriptor = kotlinx.serialization.internal.PrimitiveSerialDescriptor(name, kind)
