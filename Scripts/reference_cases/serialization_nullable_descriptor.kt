@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)

import kotlinx.serialization.descriptors.*

annotation class NullableTag(val value: String)

class MutableDescriptor(
    override var serialName: String,
    override var isNullable: Boolean = false,
    override var isInline: Boolean = true
) : SerialDescriptor {
    override var kind: SerialKind = StructureKind.CLASS
    override var elementsCount: Int = 2
    override var annotations: List<Annotation> = listOf(NullableTag("root"))
    val child: SerialDescriptor = PrimitiveSerialDescriptor("custom.Child", PrimitiveKind.STRING)
    val fieldTags: List<Annotation> = listOf(NullableTag("field"))
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

class ExplosiveNames(private val alreadyNullable: Boolean) : SerialDescriptor by
    PrimitiveSerialDescriptor("custom.Explosive", PrimitiveKind.INT) {
    override val isNullable: Boolean get() = alreadyNullable
    override val elementsCount: Int get() = 1
    override fun getElementName(index: Int): String = throw IllegalStateException("names explode")
}

fun requireElementFailure(message: String, action: () -> Any?) {
    try {
        action()
        error("missing failure")
    } catch (e: IndexOutOfBoundsException) {
        check(e.message == message)
    }
}

fun main() {
    val primitive = PrimitiveSerialDescriptor("custom.Text", PrimitiveKind.STRING)
    val wrapped = primitive.nullable
    val equal = PrimitiveSerialDescriptor("custom.Text", PrimitiveKind.STRING).nullable
    check(wrapped !== primitive)
    check(wrapped.serialName == "custom.Text?")
    check(wrapped.isNullable && !wrapped.isInline)
    check(wrapped.kind === primitive.kind && wrapped.elementsCount == 0 && wrapped.annotations.isEmpty())
    check(wrapped.nullable === wrapped)
    check(wrapped.nonNullOriginal === primitive && primitive.nonNullOriginal === primitive)
    check(wrapped == equal && equal == wrapped && wrapped !== equal)
    check(wrapped.hashCode() == primitive.hashCode() * 31 && equal.hashCode() == wrapped.hashCode())
    check(wrapped.toString() == "PrimitiveDescriptor(custom.Text)?")
    check(wrapped != primitive && primitive != wrapped)
    check(wrapped != PrimitiveSerialDescriptor("custom.Other", PrimitiveKind.STRING).nullable)
    check(wrapped != PrimitiveSerialDescriptor("custom.Text", PrimitiveKind.INT).nullable)
    check(!wrapped.equals(null) && !wrapped.equals("custom.Text?"))
    println("primitive:${wrapped.serialName}:${wrapped.hashCode()}")

    val original = MutableDescriptor("Record")
    val descriptor = original.nullable
    check(original.nameReads == 2)
    check(descriptor.serialName == "Record?" && descriptor.isNullable && descriptor.isInline)
    check(descriptor.kind === original.kind && descriptor.elementsCount == 2)
    check(descriptor.annotations === original.annotations)
    check((descriptor.annotations[0] as NullableTag).value == "root")
    check(descriptor.getElementName(0) == "shared" && descriptor.getElementName(1) == "shared")
    check(original.nameReads == 4)
    check(descriptor.getElementIndex("shared") == 0 && descriptor.getElementIndex("unknown") == -3)
    check(descriptor.getElementDescriptor(0) === original.child)
    check(descriptor.getElementDescriptor(1) === original.child)
    check(descriptor.getElementAnnotations(0) === original.fieldTags)
    check((descriptor.getElementAnnotations(0)[0] as NullableTag).value == "field")
    check(descriptor.getElementAnnotations(1).isEmpty())
    check(!descriptor.isElementOptional(0) && descriptor.isElementOptional(1))
    check(descriptor.nonNullOriginal === original)
    check(descriptor == original.nullable)
    check(descriptor != MutableDescriptor("Record").nullable)
    check(descriptor.hashCode() == 3813 && descriptor.toString() == "Record(2)?")
    println("delegation:all-eleven")

    original.serialName = "Renamed"
    original.isNullable = true
    original.isInline = false
    original.kind = StructureKind.LIST
    original.elementsCount = 3
    original.annotations = listOf(NullableTag("changed"))
    original.hash = Int.MAX_VALUE
    check(descriptor.serialName == "Record?" && descriptor.isNullable && !descriptor.isInline)
    check(descriptor.kind === StructureKind.LIST && descriptor.elementsCount == 3)
    check(descriptor.annotations === original.annotations)
    check((descriptor.annotations[0] as NullableTag).value == "changed")
    check(descriptor.getElementName(2) == "third" && descriptor.getElementIndex("third") == 2)
    check(descriptor.getElementDescriptor(2) === original.child && !descriptor.isElementOptional(2))
    check(descriptor.hashCode() == Int.MAX_VALUE * 31)
    check(descriptor.toString() == "Renamed(3)?")
    check(descriptor.nonNullOriginal === original && descriptor.nullable === descriptor)
    println("snapshot-name:live-delegation:${descriptor.hashCode()}")

    for (index in listOf(-1, 3, Int.MAX_VALUE)) {
        requireElementFailure("name:$index") { descriptor.getElementName(index) }
        requireElementFailure("descriptor:$index") { descriptor.getElementDescriptor(index) }
        requireElementFailure("annotations:$index") { descriptor.getElementAnnotations(index) }
        requireElementFailure("optional:$index") { descriptor.isElementOptional(index) }
    }
    println("errors:preserved")

    val manual = MutableDescriptor("Manual?", true)
    check(manual.nullable === manual && manual.nonNullOriginal === manual && manual.nameReads == 0)
    check(manual.isNullable && manual.serialName == "Manual?")
    val explosive = ExplosiveNames(false)
    try {
        explosive.nullable
        error("missing eager failure")
    } catch (e: IllegalStateException) {
        check(e.message == "names explode")
    }
    val alreadyNullable = ExplosiveNames(true)
    check(alreadyNullable.nullable === alreadyNullable && alreadyNullable.nonNullOriginal === alreadyNullable)
    println("identity-and-eager-cache")
}
