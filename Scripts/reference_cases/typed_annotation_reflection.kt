package typedannotations

import kotlin.reflect.KClass
import kotlin.reflect.full.findAnnotation

enum class Level { LOW, HIGH }
annotation class Nested(val text: String)
annotation class Named(
    val value: String,
    val amount: Int = 7,
    val level: Level = Level.HIGH,
    val codes: IntArray = [1, 2],
    val kind: KClass<*> = String::class,
    val nested: Nested = Nested("default"),
    val names: Array<String> = ["first", "second"]
)
@Named("wire.Record", amount = 9, codes = [3, 4], nested = Nested("inside"))
class Record
@Named(value = "wire.Default")
class Defaults
class Carrier { annotation class Tag(val value: String = "nested") }
@Carrier.Tag class NestedTagged
object Marker
annotation class Constants(val maximum: Int, val byte: Byte, val kind: KClass<*>)
@Constants(Int.MAX_VALUE, 1.toByte(), Marker::class) class ConstantRecord
annotation class Many(vararg val values: Int)
@Many(values = [1, 2]) class VarargRecord
@Target(allowedTargets = [AnnotationTarget.CLASS]) annotation class ClassOnly
@ClassOnly class TargetRecord
@Nested("constant:${1 + 2}") class TemplateRecord
annotation class ForwardTag(val value: Int)
@ForwardTag(FORWARD) class ForwardRecord
const val LATER: Int = 12
const val FORWARD: Int = LATER
private annotation class PrivateInlineTag
@PrivateInlineTag inline fun inlineMarked() {}
@Nested("callable") fun markedCallable() {}
inline fun <reified T : Annotation> lookup(kind: KClass<*>): T? = kind.findAnnotation<T>()

fun main() {
    val tags = Record::class.annotations
    check(tags.size == 1 && tags[0] is Named)
    val value = tags.filterIsInstance<Named>().single()
    check(value.value == "wire.Record" && value.amount == 9)
    check(value.level == Level.HIGH && value.codes.contentEquals(intArrayOf(3, 4)))
    check(value.kind == String::class && value.nested.text == "inside")
    check(value.names.contentEquals(arrayOf("first", "second")))
    val direct = Named("wire.Record", 9, Level.HIGH, intArrayOf(3, 4), String::class, Nested("inside"))
    check(value == direct && value.hashCode() == direct.hashCode())
    check(value.annotationClass == Named::class)
    val found = Record::class.findAnnotation<Named>()!!
    check(found.value == value.value && found == value)
    val defaults = Defaults::class.findAnnotation<Named>()!!
    check(defaults.value == "wire.Default" && defaults.amount == 7)
    check(defaults.level == Level.HIGH && defaults.codes.contentEquals(intArrayOf(1, 2)))
    check(defaults.kind == String::class && defaults.nested == Nested("default"))
    check(defaults.names.contentEquals(arrayOf("first", "second")))
    val nestedTag = NestedTagged::class.findAnnotation<Carrier.Tag>()!!
    check(nestedTag.value == "nested" && nestedTag == Carrier.Tag())
    check(nestedTag.hashCode() == Carrier.Tag().hashCode())
    check(nestedTag.toString().contains("Tag") && nestedTag.toString().contains("nested"))
    check(NestedTagged::class.annotations.single().annotationClass.simpleName == "Tag")
    val inferred: Named? = Record::class.findAnnotation()
    check(inferred == value)
    val runtimeClass = Record::class
    val inferredVariable: Named? = runtimeClass.findAnnotation()
    check(inferredVariable == value)
    val constants = ConstantRecord::class.findAnnotation<Constants>()!!
    check(constants.maximum == Int.MAX_VALUE && constants.byte == 1.toByte() && constants.kind == Marker::class)
    check(VarargRecord::class.findAnnotation<Many>()!!.values.contentEquals(intArrayOf(1, 2)))
    check(TargetRecord::class.findAnnotation<ClassOnly>() != null)
    check(TemplateRecord::class.findAnnotation<Nested>()!!.text == "constant:3")
    check(ForwardRecord::class.findAnnotation<ForwardTag>()!!.value == 12)
    check(Record::class.findAnnotation<Annotation>() is Named)
    val inferredUpper: Any? = Record::class.findAnnotation()
    check(inferredUpper is Named)
    check(lookup<Named>(Record::class) == value)
    check(lookup<Annotation>(Record::class) is Named)
    check((::markedCallable).annotations.filterIsInstance<Nested>().single().text == "callable")
    inlineMarked()
    println("constants:object-class:vararg:inferred")
    println("typed:properties:constructor:wire.Record:9")
    println("enum:arrays:class-literal:nested:defaults")
    println("equality:hash:annotationClass:findAnnotation")
}
