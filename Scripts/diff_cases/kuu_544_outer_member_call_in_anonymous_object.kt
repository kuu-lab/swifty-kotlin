interface Getter<E> {
    fun fetch(index: Int): E
}

class ConstGetter(val value: Int) : Getter<Int> {
    override fun fetch(index: Int): Int = value + index

    fun call(): Int {
        val result = object : Any() {
            fun compute(): Int = fetch(3)
        }
        return result.compute()
    }

    fun callLabeledThis(): Int {
        val result = object : Any() {
            fun compute(): Int = this@ConstGetter.fetch(1)
        }
        return result.compute()
    }
}

fun main() {
    println(ConstGetter(7).call())
    println(ConstGetter(7).callLabeledThis())
}
