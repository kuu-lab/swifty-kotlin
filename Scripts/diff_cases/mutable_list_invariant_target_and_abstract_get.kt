class Probe : AbstractMutableList<Int>() {
    private val data = mutableListOf(10, 20, 30)
    override val size: Int get() = data.size
    override fun get(index: Int): Int = data[index]
    override fun set(index: Int, element: Int): Int {
        val old = data[index]
        data[index] = element
        return old
    }
    override fun add(index: Int, element: Int) { data.add(index, element) }
    override fun removeAt(index: Int): Int = data.removeAt(index)
}

fun main() {
    // `operator get` of an AbstractMutableList subclass through index syntax.
    val p = Probe()
    println(p[1])
    p[1] = 25
    println(p[1])
    println(25 in p)
    val first: Int = p[0]
    println(first)

    // Invariant mutable targets take their element type from the target.
    val numbers: MutableList<Number> = mutableListOf(77)
    numbers.add(1.5)
    println(numbers)
    val anything: MutableList<Any?> = mutableListOf(1, "s")
    anything.add(null)
    println(anything)
    val boxes: ArrayList<Any> = arrayListOf(1)
    boxes.add("s")
    println(boxes)
}
