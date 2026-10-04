class Node(val value: Int, val nextNode: Node?) {
    fun next(): Node? = nextNode
}

fun describe(any: Any?): String {
    var current = any
    if (current is String) {
        return "string:" + current.length
    }
    if (current is Int) {
        return "int:" + (current + 1)
    }
    current = null
    return "other:" + (current == null)
}

fun countUp(start: Int?): Int {
    var value = start
    var total = 0
    while (value != null) {
        total = total + value
        value = if (value < 3) value + 1 else null
    }
    return total
}

fun main() {
    var node: Node? = Node(1, Node(2, Node(3, null)))
    while (node != null) {
        println(node.value)
        node = node.next()
    }
    println(describe("abc"))
    println(describe(41))
    println(describe(1.5))
    println(countUp(1))
    println(countUp(null))
}
