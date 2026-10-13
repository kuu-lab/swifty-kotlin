@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*

@SerialInfo
@Target(AnnotationTarget.CLASS, AnnotationTarget.PROPERTY)
annotation class SerialTag(val value: String)

@InheritableSerialInfo
@Target(AnnotationTarget.CLASS)
annotation class InheritedTag(val value: Int)

@SerialName("wire.Record")
@SerialTag("record")
@InheritedTag(7)
class TaggedRecord(@SerialName("field") val value: Int)

fun main() {
    val serialName = SerialName(value = "wire.Record")
    check(serialName.value == "wire.Record" && SerialName("").value == "" && SerialName(" ").value == " ")
    val runtimeName = "wire." + TaggedRecord::class.simpleName
    check(SerialName(runtimeName).value == runtimeName)
    check(serialName == SerialName("wire.Record") && serialName != SerialName("other"))
    check(serialName.hashCode() == ((127 * "value".hashCode()) xor "wire.Record".hashCode()))
    check(SerialInfo() == SerialInfo() && SerialInfo().hashCode() == 0)
    check(InheritableSerialInfo() == InheritableSerialInfo() && InheritableSerialInfo().hashCode() == 0)
    check(serialName.annotationClass.simpleName == "SerialName")
    val tags = TaggedRecord::class.annotations
    check(tags.filterIsInstance<SerialName>().single().value == "wire.Record")
    check(tags.filterIsInstance<SerialTag>().single().value == "record")
    check(tags.filterIsInstance<InheritedTag>().single().value == 7)
    check(SerialTag::class.annotations.none { it is SerialInfo })
    check(InheritedTag::class.annotations.none { it is InheritableSerialInfo })
    val child = PrimitiveSerialDescriptor("Child", PrimitiveKind.INT)
    val descriptor = buildClassSerialDescriptor("Record") {
        annotations = listOf(serialName, SerialTag("root"), InheritedTag(9))
        element("field", child, annotations = listOf(SerialName("wire.field"), SerialTag("field")))
    }
    check(descriptor.serialName == "Record" && descriptor.getElementName(0) == "field")
    check(descriptor.annotations.size == 3 && descriptor.getElementAnnotations(0).size == 2)
    check(descriptor.annotations[0] === serialName && descriptor.annotations[1] is SerialTag && descriptor.annotations[2] is InheritedTag)
    check(descriptor.annotations.filterIsInstance<SerialName>().single() === serialName)
    check(descriptor.annotations.filterIsInstance<SerialTag>().single().value == "root")
    check(descriptor.annotations.filterIsInstance<InheritedTag>().single().value == 9)
    check(descriptor.getElementAnnotations(0).filterIsInstance<SerialName>().single().value == "wire.field")
    check(descriptor.getElementAnnotations(0).filterIsInstance<SerialTag>().single().value == "field")
    println("annotations:value:equality:hash")
    println("retention:runtime:binary")
    println("descriptor:root:field:identity")
}
