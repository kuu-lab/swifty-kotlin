class Outer<V : Any>(val initial: V) {
    inner class Values : AbstractMutableList<V>() {
        private val data = mutableListOf<V>(initial)
        override val size: Int get() = data.size
        override fun get(index: Int): V = data[index]
        override fun set(index: Int, element: V): V = data.set(index, element)
        override fun add(index: Int, element: V) { data.add(index, element) }
        override fun removeAt(index: Int): V = data.removeAt(index)

        fun <U : V> echo(value: U): V = value
        fun <V> shadow(value: V): V = value
    }

    inner class Middle<W>(val second: W) {
        inner class Deep {
            val first: V = initial
            fun show(): String = first.toString() + "/" + second.toString()
        }
        fun show(): String = Deep().show()
    }

    fun exercise(): String {
        val values = Values()
        values.add(initial)
        val old: V = values.set(0, initial)
        val echoed: V = values.echo(initial)
        val removed: V = values.removeAt(1)
        val shadowed: Int = values.shadow(7)
        return "${values.size}:$old:$echoed:$removed:$shadowed"
    }

    fun nested(): String = Middle(9).show()
}

fun main() {
    val strings = Outer("value")
    println(strings.exercise())
    println(strings.nested())
    val numbers = Outer(42)
    println(numbers.exercise())
    println(numbers.nested())
}
