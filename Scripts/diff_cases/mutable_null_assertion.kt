package nullassertreference

class Node(val value: Int, val next: Node?)
fun read(node: Node): Int = node.value
fun next(node: Node): Node? = node.next

fun chain(first: Node?): Int {
    var node = first
    var total = 0
    do {
        node!!
        total += read(node)
        node = next(node)
    } while (node != null)
    return total
}

fun lambdaChain(first: Node?): Int {
    val action = {
        var node = first
        var total = 0
        do {
            node!!
            total += read(node)
            node = next(node)
        } while (node != null)
        total
    }
    return action()
}

fun reassignedAfterAssert(first: Node?): Int {
    var node = first
    node!!
    val total = read(node)
    node = null
    return total + if (node == null) 1 else 0
}

fun main() {
    val first = Node(3, Node(4, null))
    println(chain(first))
    println(lambdaChain(first))
    println(reassignedAfterAssert(first))
}
