import kotlin.reflect.KClass

data class WithDefault(val value: String = "fallback")

fun main() {
    val constructor = WithDefault::class.constructors.single()
    println("parameters=${constructor.parameters.size}")
    try {
        val instance = constructor.callBy(emptyMap()) as WithDefault
        println("value=${instance.value}")
    } catch (error: Throwable) {
        println("callBy failed: ${error.message}")
    }
}
