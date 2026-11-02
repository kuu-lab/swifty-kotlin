interface Box<T>
val cond = true
class ImplA : Box<Any?>
class ImplB : Box<Any>

fun probe(a: Box<Any?>, b: Box<out Any>): Box<out Any?> = if (cond) a else b

fun main() {
    println(probe(ImplA(), ImplB()) != null)
}
