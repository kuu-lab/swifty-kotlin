import kotlin.reflect.KProperty

val four: Int by NumberDecrypter

object NumberDecrypter {
    operator fun getValue(instance: Any?, data: KProperty<*>) = 4
}

fun main() { println(four) }
