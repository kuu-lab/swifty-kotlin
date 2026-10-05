interface CMap<K, V> : MutableMap<K, V> {
    fun remove(key: K, value: V): Boolean
    override fun remove(key: K): V?
}

interface ReversedCMap<K, V> : MutableMap<K, V> {
    override fun remove(key: K): V?
    fun remove(key: K, value: V): Boolean
}

open class Base {
    open fun remove(key: Int): Int = key
    open val value: Int = 1
}

open class OpenChild : Base() {
    fun remove(key: Int, value: Int): Boolean = key == value
    override fun remove(key: Int): Int = key + 1
}

class FinalChild : Base() {
    fun remove(key: Int, value: Int): Boolean = key == value
    final override fun remove(key: Int): Int = key + 2
}

class PropertyChild : Base() {
    fun value(key: Int): Int = key
    override val value: Int = 2
}

fun main() {
    val open = OpenChild()
    println(open.remove(3))
    println(open.remove(3, 3))
    val final = FinalChild()
    println(final.remove(3))
    println(final.remove(3, 4))
    val property = PropertyChild()
    println(property.value)
    println(property.value(7))
}
