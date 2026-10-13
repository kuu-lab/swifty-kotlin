import kotlin.reflect.KClass
fun main() {
    val classifier = Number::class.supertypes[1].classifier
    try {
        val k = classifier as KClass<Any>
        println(k.qualifiedName)
    } catch (e: ClassCastException) {
        println("ClassCastException")
    }
}
