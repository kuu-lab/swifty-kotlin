// KUU-1910: inferred nested Node returns must be available inside generic getters.
// KOTLINC_FLAGS: -Xjdk-release=17
class Chain<T>(private var head: Node<T>?) {
    val list: List<T>
        get() {
            val nodes = mutableListOf<T>()
            var node = head
            while (node != null) {
                val value = node.value()
                if (value != null) nodes.add(value)
                node = node.next()
            }
            return nodes
        }

    val reversedList: List<T>
        get() {
            val nodes = mutableListOf<T>()
            var node = head
            while (node != null) {
                val value = node.value()
                if (value != null) nodes.add(value)
                node = node.previous()
            }
            return nodes
        }

    fun count(): Int {
        var node = head
        var count = 0
        while (node != null) {
            count++
            node = node.next()
        }
        return count
    }

    class Node<T>(
        private var value: T? = null,
        private var previous: Node<T>? = null,
        private var next: Node<T>? = null
    ) {
        fun next() = next
        fun previous() = previous
        fun value() = value
    }
}

fun main() {
    val tail = Chain.Node(value = 2)
    val head = Chain.Node(value = 1, next = tail)
    println(Chain(head).list)
    println(Chain(head).count())

    val first = Chain.Node(value = 1)
    val last = Chain.Node(value = 2, previous = first)
    println(Chain(last).reversedList)

    val empty = Chain<Int>(null)
    println(empty.list)
    println(empty.reversedList)
    println(empty.count())

    val single = Chain(Chain.Node(value = "only"))
    println(single.list)
    println(single.reversedList)
    println(single.count())

    val end = Chain.Node(value = "end")
    val gap = Chain.Node<String>(next = end)
    println(Chain(gap).list)
    println(Chain(gap).count())

    val backEnd = Chain.Node(value = "start")
    val backGap = Chain.Node<String>(previous = backEnd)
    println(Chain(backGap).reversedList)
}
