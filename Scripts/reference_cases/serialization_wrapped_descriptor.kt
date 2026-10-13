@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)

import kotlinx.serialization.descriptors.*

annotation class WrappedTag(val value: String)

class WrappedInput(
    override var serialName: String,
    override var isNullable: Boolean = false,
    override var isInline: Boolean = true
) : SerialDescriptor {
    override var kind: SerialKind = StructureKind.CLASS
    override var elementsCount: Int = 2
    override var annotations: List<Annotation> = listOf(WrappedTag("root"))
    val child: SerialDescriptor = PrimitiveSerialDescriptor("custom.Child", PrimitiveKind.STRING)
    val fieldTags: List<Annotation> = listOf(WrappedTag("field"))
    var nameReads: Int = 0
    var hash: Int = 123
    override fun getElementName(index: Int): String {
        nameReads++
        return when (index) {
            0, 1 -> "shared"
            2 -> "third"
            else -> throw IndexOutOfBoundsException("name:$index")
        }
    }
    override fun getElementIndex(name: String): Int = when (name) {
        "shared" -> 0
        "third" -> 2
        else -> -3
    }
    override fun getElementDescriptor(index: Int): SerialDescriptor = when (index) {
        0, 1, 2 -> child
        else -> throw IndexOutOfBoundsException("descriptor:$index")
    }
    override fun getElementAnnotations(index: Int): List<Annotation> = when (index) {
        0 -> fieldTags
        1, 2 -> emptyList()
        else -> throw IndexOutOfBoundsException("annotations:$index")
    }
    override fun isElementOptional(index: Int): Boolean = when (index) {
        0, 2 -> false
        1 -> true
        else -> throw IndexOutOfBoundsException("optional:$index")
    }
    override fun hashCode(): Int = hash
    override fun toString(): String = "$serialName($elementsCount)"
}

fun requireFailure(message: String, action: () -> Any?) {
    try { action(); error("missing failure") }
    catch (e: IllegalArgumentException) { check(e.message == message) }
}

fun requireElementFailure(message: String, action: () -> Any?) {
    try { action(); error("missing failure") }
    catch (e: IndexOutOfBoundsException) { check(e.message == message) }
}

fun main() {
    val primitive = PrimitiveSerialDescriptor("custom.Text", PrimitiveKind.STRING)
    val renamed = SerialDescriptor("Alias.Text", primitive)
    val equal = SerialDescriptor("Alias.Text", PrimitiveSerialDescriptor("custom.Text", PrimitiveKind.STRING))
    check(renamed !== primitive && renamed.serialName == "Alias.Text")
    check(!renamed.isNullable && !renamed.isInline && renamed.kind === PrimitiveKind.STRING)
    check(renamed.elementsCount == 0 && renamed.annotations.isEmpty())
    check(renamed == equal && equal == renamed && renamed !== equal)
    check(renamed.hashCode() == "Alias.Text".hashCode() * 31 + primitive.hashCode())
    check(renamed.toString() == "Alias.Text()")
    check(renamed != primitive && primitive != renamed)
    check(renamed != SerialDescriptor("Other.Text", primitive))
    check(renamed != SerialDescriptor("Alias.Text", PrimitiveSerialDescriptor("other", PrimitiveKind.STRING)))
    check(!renamed.equals(null) && !renamed.equals("Alias.Text"))
    println("primitive:${renamed.serialName}:${renamed.hashCode()}")

    val original = WrappedInput("Record")
    val descriptor = SerialDescriptor("Alias.Record", original)
    check(original.nameReads == 0)
    check(descriptor.serialName == "Alias.Record" && !descriptor.isNullable && descriptor.isInline)
    check(descriptor.kind === original.kind && descriptor.elementsCount == 2)
    check(descriptor.annotations === original.annotations)
    check((descriptor.annotations[0] as WrappedTag).value == "root")
    check(descriptor.getElementName(0) == "shared" && descriptor.getElementName(1) == "shared")
    check(descriptor.getElementIndex("shared") == 0 && descriptor.getElementIndex("unknown") == -3)
    check(descriptor.getElementDescriptor(0) === original.child)
    check(descriptor.getElementAnnotations(0) === original.fieldTags)
    check((descriptor.getElementAnnotations(0)[0] as WrappedTag).value == "field")
    check(descriptor.getElementAnnotations(1).isEmpty())
    check(!descriptor.isElementOptional(0) && descriptor.isElementOptional(1))
    check(descriptor == SerialDescriptor("Alias.Record", original))
    check(descriptor != SerialDescriptor("Alias.Record", WrappedInput("Record")))
    check(descriptor.toString() == "Alias.Record(shared: custom.Child, shared: custom.Child)")
    println("delegation:all-eleven")

    original.serialName = "Changed"
    original.isNullable = true
    original.isInline = false
    original.kind = StructureKind.MAP
    original.elementsCount = 3
    original.annotations = listOf(WrappedTag("changed"))
    original.hash = Int.MAX_VALUE
    check(descriptor.serialName == "Alias.Record" && descriptor.isNullable && !descriptor.isInline)
    check(descriptor.kind === StructureKind.MAP && descriptor.elementsCount == 3)
    check(descriptor.annotations === original.annotations)
    check((descriptor.annotations[0] as WrappedTag).value == "changed")
    check(descriptor.getElementName(2) == "third" && descriptor.getElementIndex("third") == 2)
    check(descriptor.getElementDescriptor(2) === original.child && !descriptor.isElementOptional(2))
    check(descriptor.hashCode() == "Alias.Record".hashCode() * 31 + Int.MAX_VALUE)
    check(descriptor.toString() == "Alias.Record(shared: custom.Child, shared: custom.Child, third: custom.Child)")
    check(SerialDescriptor("Nested", descriptor).toString() == "Nested(shared: custom.Child, shared: custom.Child, third: custom.Child)")
    println("snapshot-name:live-delegation:${descriptor.hashCode()}")

    for (index in listOf(-1, 3, Int.MAX_VALUE)) {
        requireElementFailure("name:$index") { descriptor.getElementName(index) }
        requireElementFailure("descriptor:$index") { descriptor.getElementDescriptor(index) }
        requireElementFailure("annotations:$index") { descriptor.getElementAnnotations(index) }
        requireElementFailure("optional:$index") { descriptor.isElementOptional(index) }
    }
    for (blank in listOf("", " ", "\t", "\n", " \r\n\t", "\u00a0", "\u2000", "\u3000")) {
        requireFailure("Blank serial names are prohibited") { SerialDescriptor(blank, primitive) }
    }
    requireFailure("The name of the wrapped descriptor (custom.Text) cannot be the same as the name of the original descriptor (custom.Text)") {
        SerialDescriptor("custom.Text", primitive)
    }
    requireFailure("The name of serial descriptor should uniquely identify associated serializer.\nFor serial name kotlin.Int there already exists IntSerializer.\nPlease refer to SerialDescriptor documentation for additional information.") {
        SerialDescriptor("kotlin.Int", primitive)
    }
    val blankOriginal = WrappedInput("")
    requireFailure("Blank serial names are prohibited") { SerialDescriptor("", blankOriginal) }
    val reservedOriginal = WrappedInput("kotlin.Int")
    reservedOriginal.kind = PrimitiveKind.INT
    requireFailure("The name of the wrapped descriptor (kotlin.Int) cannot be the same as the name of the original descriptor (kotlin.Int)") {
        SerialDescriptor("kotlin.Int", reservedOriginal)
    }
    check(SerialDescriptor("kotlin.Int", original).serialName == "kotlin.Int")
    println("errors:preserved:validation-order")
}
