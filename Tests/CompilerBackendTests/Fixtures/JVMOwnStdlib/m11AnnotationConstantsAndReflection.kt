import kotlin.reflect.KClass
import kotlin.reflect.full.findAnnotation
import kotlin.reflect.full.memberProperties
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION, AnnotationTarget.FIELD, AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.VALUE_PARAMETER)
annotation class Label(val text: String, val count: Int = 2 * 3)
enum class Kind { ONE, TWO }
annotation class Details(val label: Label, val kind: Kind, val numbers: IntArray, val type: KClass<*>, val types: Array<KClass<*>>)
@Label("box", 42)
@Details(Label("nested"), Kind.TWO, [1, 2, 3], Box::class, [Int::class, Box::class])
class Box(@field:Label("field") @get:Label("getter") var value: Int)
@Label("function") fun tagged(@Label("parameter") n: Int): Int = n
fun main() {
    println(Box::class.annotations.size)
    val label = Box::class.findAnnotation<Label>()!!
    println(label.text); println(label.count)
    val details = Box::class.findAnnotation<Details>()!!
    println(details.label.text); println(details.kind); println(details.numbers[1]); println(details.type.simpleName); println(details.types[0].simpleName)
    println(Box::class.memberProperties.size)
    println(::tagged.annotations.size)
    println(Box::class.java.getAnnotation(Label::class.java)!!.text)
}
