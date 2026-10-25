class Source<out T>(val value: T)
class Sink<in T> { fun accept(value: T) {} }
class Box<T>(val value: T)
typealias View<T> = Box<T>
typealias Consumer<T> = (T) -> Unit
typealias Producer<T> = () -> T

fun read(source: Source<out Int>): Int = source.value
fun write(sink: Sink<in Int>) { sink.accept(7) }
fun readView(view: View<out Int>): Int = view.value

fun main() {
    println(read(Source(3)))
    write(Sink<Int>())
    println(readView(Box(5)))
    val consume: Consumer<in Int> = { println(it) }
    val produce: Producer<out Int> = { 9 }
    consume(produce())
}
