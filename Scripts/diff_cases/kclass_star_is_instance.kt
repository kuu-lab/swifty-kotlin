import kotlin.reflect.KClass
fun main() {
    val k: KClass<*> = Int::class
    println(k.isInstance(42))
}
