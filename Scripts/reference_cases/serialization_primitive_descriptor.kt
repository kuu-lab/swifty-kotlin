@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)

import kotlinx.serialization.descriptors.*

fun customPrimitive(name: String, kind: PrimitiveKind): SerialDescriptor = PrimitiveSerialDescriptor(name, kind)

class Lookalike(override val serialName: String, override val kind: PrimitiveKind) : SerialDescriptor {
    override val elementsCount: Int get() = 0
    override fun getElementName(index: Int): String = error("lookalike")
    override fun getElementIndex(name: String): Int = error("lookalike")
    override fun isElementOptional(index: Int): Boolean = error("lookalike")
    override fun getElementDescriptor(index: Int): SerialDescriptor = error("lookalike")
    override fun getElementAnnotations(index: Int): List<Annotation> = error("lookalike")
}

fun expectPrimitiveFailure(name: String, message: String, action: () -> Any?) {
    try {
        action()
        error("Expected primitive failure: $name")
    } catch (e: IllegalStateException) {
        check(e.message == message) { "$name: ${e.message}" }
    }
}

fun expectNameFailure(name: String, message: String) {
    try {
        customPrimitive(name, PrimitiveKind.STRING)
        error("Expected invalid name: $name")
    } catch (e: IllegalArgumentException) {
        check(e.message == message) { "$name: ${e.message}" }
    }
}

fun main() {
    val kinds = listOf(PrimitiveKind.BOOLEAN, PrimitiveKind.BYTE, PrimitiveKind.SHORT, PrimitiveKind.INT,
        PrimitiveKind.LONG, PrimitiveKind.FLOAT, PrimitiveKind.DOUBLE, PrimitiveKind.CHAR, PrimitiveKind.STRING)
    for (kind in kinds) {
        val name = "custom.$kind"
        val descriptor = customPrimitive(name, kind)
        check(descriptor.serialName == name)
        check(descriptor.kind === kind)
        check(descriptor.elementsCount == 0)
        check(!descriptor.isNullable && !descriptor.isInline)
        check(descriptor.annotations.isEmpty())
        check(descriptor.toString() == "PrimitiveDescriptor($name)")
        check(descriptor == descriptor)
        val same = customPrimitive(name, kind)
        check(descriptor == same && same == descriptor && descriptor !== same)
        check(descriptor.hashCode() == same.hashCode())
        check(descriptor != customPrimitive("other.$kind", kind))
        val otherKind = if (kind == PrimitiveKind.STRING) PrimitiveKind.INT else PrimitiveKind.STRING
        check(descriptor != customPrimitive(name, otherKind))
        check(!descriptor.equals(null) && !descriptor.equals(name))
        check(descriptor != Lookalike(name, kind))
        println("$kind:${descriptor.hashCode()}")
        val message = "Primitive descriptor $name does not have elements"
        for (index in listOf(-1, 0, 1, Int.MAX_VALUE)) {
            expectPrimitiveFailure("name", message) { descriptor.getElementName(index) }
            expectPrimitiveFailure("optional", message) { descriptor.isElementOptional(index) }
            expectPrimitiveFailure("descriptor", message) { descriptor.getElementDescriptor(index) }
            expectPrimitiveFailure("annotations", message) { descriptor.getElementAnnotations(index) }
        }
        for (element in listOf("", "0", "value")) {
            expectPrimitiveFailure("index", message) { descriptor.getElementIndex(element) }
        }
    }
    println("elements:all-five")
    for (name in listOf("", " ", "\t\n\r", "\u000B", "\u00A0", "\u2003", "\u202F", "\u3000")) {
        expectNameFailure(name, "Blank serial names are prohibited")
    }
    println("blank:8")
    val reserved = listOf("String", "Char", "CharArray", "Double", "DoubleArray", "Float", "FloatArray",
        "Long", "LongArray", "ULong", "ULongArray", "Int", "IntArray", "UInt", "UIntArray",
        "Short", "ShortArray", "UShort", "UShortArray", "Byte", "ByteArray", "UByte", "UByteArray",
        "Boolean", "BooleanArray", "Unit", "Nothing", "time.Duration", "time.Instant", "uuid.Uuid")
    for (type in reserved) {
        val name = "kotlin.$type"
        val simpleName = type.substringAfterLast('.')
        val message = "The name of serial descriptor should uniquely identify associated serializer.\nFor serial name $name there already exists ${simpleName}Serializer.\nPlease refer to SerialDescriptor documentation for additional information."
        expectNameFailure(name, message)
    }
    println("reserved:30")
    for (name in listOf("kotlin.collections.ArrayList", "kotlin.collections.HashMap", " kotlin.String", "x\u200B", "\u200B")) {
        check(customPrimitive(name, PrimitiveKind.INT).serialName == name)
    }
    println("valid:5")
}
