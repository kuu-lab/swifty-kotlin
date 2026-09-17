// KUU-602: a qualified outer `this` in an object literal property initializer
// must retain the enclosing receiver after the object receiver is installed.
class Node(val v: Int) : Iterable<Int> {
    var next: Node? = null
    override fun iterator(): Iterator<Int> {
        return object : Iterator<Int> {
            var cur: Node? = this@Node
            override fun hasNext() = cur != null
            override fun next(): Int {
                val n = cur!!
                cur = n.next
                return n.v
            }
        }
    }
}

fun main() {
    val n = Node(1)
    n.next = Node(2)
    val it = n.iterator()
    println(it.hasNext())
    println(it.next())
    println(it.next())
    println(it.hasNext())
    for (v in n) print(v)
    println()
}
