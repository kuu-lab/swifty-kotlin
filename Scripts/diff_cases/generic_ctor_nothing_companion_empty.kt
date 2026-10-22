class Node<K, V>(val x: Int) {
    companion object { val EMPTY = Node<Nothing, Nothing>(0) }
}

class Box<K, V>(val node: Node<K, V>, val i: Int)

fun main() {
    val e = Box(Node.EMPTY, 0)
    println(e.node.x)
    println(e.i)
    val explicit = Box<Nothing, Nothing>(Node.EMPTY, 1)
    println(explicit.i)
}
