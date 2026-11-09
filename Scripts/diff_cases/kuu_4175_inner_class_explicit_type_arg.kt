// DIFF_JVM
// KUU-4175: explicit call type arguments inside an inner class body must
// keep the implicit enclosing instance's type arguments. `Box<Handler?>`
// previously dropped `Outer<T>`'s argument, so `_box.v` mismatched every
// declared `Handler?` accessor (kotlinx.coroutines AwaitAllNode.disposer,
// KSWIFTK-SEMA-0469/0470).
class Box<V>(var v: V)

class Outer<T>(val tag: T) {
    inner class Handler(val name: String)

    inner class Node {
        private val _box = Box<Handler?>(null)

        var disposer: Handler?
            get() = _box.v
            set(value) { _box.v = value }

        fun install() {
            disposer = Handler("h-$tag")
        }

        fun reset() {
            disposer = Handler("manual")
        }

        fun read(): Handler? = _box.v
    }

    fun node(): Node = Node()
}

fun main() {
    val outer = Outer(7)
    val node = outer.node()
    node.install()
    println(node.read()?.name)
    node.reset()
    println(node.disposer?.name)
    val strings = Outer("s")
    val other = strings.node()
    other.install()
    println(other.read()?.name)
}
