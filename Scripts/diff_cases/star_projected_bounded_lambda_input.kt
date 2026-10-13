// KUU-1930: retain explicit non-null bounds for star receiver lambda inputs.
class Box<T : Any>(val value: T)
fun <T : Any, R> Box<T>.map(transform: (T) -> R): R = transform(value)
fun requireAny(value: Any): String = value.toString()
fun render(box: Box<*>): String = box.map { requireAny(it) }

fun main() {
    println(render(Box(3)))
}
