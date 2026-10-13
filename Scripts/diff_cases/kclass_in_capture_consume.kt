import kotlin.reflect.KClass

class CaptureBox<T>(var value: T)

fun <T : Any> KClass<T>.consume(value: T): Int = 7
fun probe(k: KClass<in Int>): Int = k.consume(42)
fun <T : Any> KClass<T>.echo(value: T): T = value
fun <T : Any> KClass<T>.boxed(value: T): CaptureBox<T> = CaptureBox(value)
fun <T : Any> KClass<T>.listed(value: T): List<T> = listOf(value)
fun <T : Any> KClass<T>.read(): T = 42 as T
fun <T : Any> KClass<T>.readValue(value: Any): T = value as T

fun main() {
    val inferred = Int::class
    val typed: KClass<Int> = Int::class
    val projected: KClass<in Int> = Int::class
    val wider: KClass<in Int> = Any::class
    val out: KClass<out Any> = Int::class
    val star: KClass<*> = Int::class
    println(inferred.consume(42))
    println(typed.consume<Int>(42))
    println(probe(projected))
    println(probe(wider))
    val value: Any = projected.echo(42)
    println(value)
    val readable: CaptureBox<out Any> = projected.boxed(42)
    println(readable.value)
    val writable: CaptureBox<in Int> = projected.boxed(42)
    writable.value = 43
    println(writable.value)
    val list: List<Any> = projected.listed(42)
    println(list[0])
    println(out.read())
    println(star.read())
    val outInt: KClass<out Int> = Int::class
    println(outInt.read() + 1)
    println(-outInt.read())
    val outString: KClass<out String> = String::class
    println(outString.readValue("a") + "x")
    val outBoolean: KClass<out Boolean> = Boolean::class
    println(!outBoolean.readValue(false))
}
