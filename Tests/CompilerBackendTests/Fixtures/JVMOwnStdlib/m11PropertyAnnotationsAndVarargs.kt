import kotlin.reflect.full.findAnnotation
@Target(AnnotationTarget.PROPERTY) annotation class PropertyTag(val name: String)
annotation class Tags(vararg val names: String = ["default"])
@Tags class DefaultMarked
object Constants { init { println("UNEXPECTED INIT") }; const val NUMBER = 42 }
@PropertyTag("top") val top = 1
class Box { @PropertyTag("member") var value = 2 }
@Tags(names = ["one", "two"]) class Marked
fun main() {
    println(::top.findAnnotation<PropertyTag>()!!.name)
    println(Box::value.findAnnotation<PropertyTag>()!!.name)
    val tags = Marked::class.findAnnotation<Tags>()!!
    println(tags.names.size); println(tags.names[0]); println(tags.names[1])
    println(DefaultMarked::class.findAnnotation<Tags>()!!.names[0]); println(Constants.NUMBER)
}
