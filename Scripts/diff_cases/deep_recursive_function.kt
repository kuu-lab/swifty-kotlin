// KSP-612: DeepRecursiveFunction / DeepRecursiveScope parity.
// Covers the implicit `it` block, an explicit lambda parameter, a capturing
// block, and a nullable input type.

class Node(val value: Int, val left: Node?, val right: Node?)

val depth = DeepRecursiveFunction<Node?, Int> { node ->
    if (node == null) 0 else maxOf(callRecursive(node.left), callRecursive(node.right)) + 1
}

val sumTo = DeepRecursiveFunction<Int, Int> {
    if (it <= 0) 0 else it + callRecursive(it - 1)
}

fun main() {
    val factorial = DeepRecursiveFunction<Int, Int> { n ->
        if (n <= 1) 1 else n * callRecursive(n - 1)
    }
    println(factorial(5))
    println(sumTo(10))

    val step = 3
    val countDown = DeepRecursiveFunction<Int, Int> { n ->
        if (n <= 0) 0 else callRecursive(n - step) + 1
    }
    println(countDown(9))

    val tree = Node(1, Node(2, Node(4, null, null), null), Node(3, null, null))
    println(depth(tree))
    println(depth(null))
}
