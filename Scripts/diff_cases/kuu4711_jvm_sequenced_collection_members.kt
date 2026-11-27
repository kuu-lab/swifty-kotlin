// DIFF_JVM
// DIFF_SKIP_NATIVE: JVM member enhancement of MutableList has no native counterpart.
// KUU-4711: java.util.SequencedCollection end members are members of
// MutableList on JVM. They win over same-signature user extensions, while
// implementors may declare matching members without an explicit override.
fun <T> MutableList<T>.addFirst(element: T) {
    add(element)
    println("extension addFirst")
}

fun <T> MutableList<T>.removeFirst(): T {
    println("extension removeFirst")
    return removeAt(size - 1)
}

interface HidingList : MutableList<Int> {
    fun addFirst(element: Int) {}
    fun addLast(element: Int) {}
    fun removeFirst(): Int = 0
    fun removeLast(): Int = 0
}

class DelegatedList : MutableList<Int> by mutableListOf(1, 2) {
    fun addFirst(element: Int) {
        println("delegated addFirst")
        add(0, element)
    }
}

class SuperRemovingMap : MutableMap<Int, String> by mutableMapOf(1 to "a") {
    override fun remove(key: Int, value: String): Boolean {
        println("override remove")
        return super<MutableMap>.remove(key, value)
    }
}

class InstrumentedDelegatedList(
    private val backing: MutableList<Int>
) : MutableList<Int> by backing {
    override fun add(element: Int): Boolean {
        println("instrumented add")
        return backing.add(element)
    }
}

fun main() {
    val values = mutableListOf(1, 2)
    values.addFirst(0)
    values.addLast(3)
    values.addFirst(element = -1)
    println(values)
    println(values.removeFirst())
    println(values.removeLast())
    println(values)

    val delegated = DelegatedList()
    delegated.addFirst(0)
    println(delegated.size)
    println(delegated[0])

    val instrumentedBacking = mutableListOf<Int>()
    val instrumented = InstrumentedDelegatedList(instrumentedBacking)
    val instrumentedAsList: MutableList<Int> = instrumented
    instrumentedAsList.addLast(9)
    println(instrumentedBacking)

    val named = mutableMapOf(1 to "a")
    println(named.remove(value = "a", key = 1))
    println(named)

    val superRemoving = SuperRemovingMap()
    println(superRemoving.remove(1, "a"))
    println(superRemoving.size)
}
