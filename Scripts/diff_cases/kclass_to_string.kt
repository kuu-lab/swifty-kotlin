// KUU-1080: Class handles must render through both typed and erased boundaries.
class Annotated

fun main() {
    println(Annotated::class)
    println(Annotated::class.toString())
    val klass = Annotated::class
    println(klass.toString())
    val erased: Any = klass
    println(erased)
    println(erased.toString())
    println("class=$klass")
    println(listOf(klass))
}
