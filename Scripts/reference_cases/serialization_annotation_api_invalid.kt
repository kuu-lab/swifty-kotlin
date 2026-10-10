@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
import kotlinx.serialization.*
@SerialName("fun") fun badNameFunction() {}
fun badParameter(@SerialName("param") value: Int) {}
class BadSites(@param:SerialName("param") @field:SerialName("field") @get:SerialName("getter") val value: Int)
@SerialInfo class NotAnnotation
@InheritableSerialInfo class NotInheritedAnnotation
@SerialInfo fun badMetaFunction() {}
@InheritableSerialInfo val badMetaProperty: Int = 1
fun badArguments() {
    SerialName()
    SerialName(null)
    SerialName(1)
    SerialName(name = "wrong")
}
fun runtimeValue(): String = "dynamic"
@SerialName(runtimeValue()) class Nonconstant
