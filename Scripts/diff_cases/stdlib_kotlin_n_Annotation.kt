import kotlin.reflect.typeOf

annotation class Marker

fun main() {
    println(typeOf<Annotation>())
    println(typeOf<Marker>())
}
