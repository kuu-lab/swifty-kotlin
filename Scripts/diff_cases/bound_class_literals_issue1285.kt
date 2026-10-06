import kotlin.reflect.KClass

fun main() {
    println(Int::class.simpleName)
    println("x"::class.simpleName)
    val s = "a"
    val stringClass: KClass<out String> = s::class
    println(stringClass.simpleName)
    println(5::class.simpleName)
    val listClass: KClass<out List<Int>> = listOf(1)::class
    println(listClass.isInstance(listOf(2)))
    val erased: Any = s
    println(erased::class == String::class)
    try {
        throw IllegalArgumentException("bound class literal")
    } catch (e: Exception) {
        println(e::class.simpleName)
        println(e::class == IllegalArgumentException::class)
    }
}
