/*
 * KUU-1858 regression for java.util.LinkedList consumers.
 * Upstream Queue.kt: https://github.com/DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns/blob/1f89f062a056e24cc289ffdd0c6e23cadf8df887/src/main/kotlin/structures/Queue.kt
 * Upstream Graph.kt: https://github.com/DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns/blob/1f89f062a056e24cc289ffdd0c6e23cadf8df887/src/main/kotlin/structures/Graph.kt
 * The first six lines are the issue's minimal input and expected output. The
 * remaining lines cover collection construction, addAll, clear, and Graph's
 * breadth-first queue operations. Empty removeFirst/first report null messages
 * on Kotlin 2.3.10/JVM.
 *
 * Expected stdout:
 * 1
 * 3
 * 3
 * 7
 * null
 * true
 * null
 * remove:null
 * first:null
 * 8
 * 4
 * true 0
 * 2,3
 */

import java.util.LinkedList

fun main() {
    val queue = LinkedList<Int>()
    queue.add(3)
    queue.add(7)
    queue.push(1)
    println(queue.pollFirst())
    println(queue.first)
    println(queue.removeFirst())
    println(queue.pollFirst())
    val empty: Int? = queue.pollFirst()
    println(empty)
    println(queue.isEmpty())

    val emptyQueue = LinkedList<Int>()
    val emptyPoll: Int? = emptyQueue.pollFirst()
    println(emptyPoll)
    try {
        emptyQueue.removeFirst()
        println("remove:no-throw")
    } catch (exception: NoSuchElementException) {
        println("remove:${exception.message}")
    }
    try {
        println(emptyQueue.first)
        println("first:no-throw")
    } catch (exception: NoSuchElementException) {
        println("first:${exception.message}")
    }

    val copied = LinkedList<Int>(listOf(8, 9))
    copied.addAll(listOf(10, 11))
    println(copied.first)
    println(copied.size)
    copied.clear()
    println("${copied.isEmpty()} ${copied.size}")

    val breadthFirstQueue = LinkedList<Int>()
    breadthFirstQueue.addAll(listOf(2, 3))
    val visited = mutableListOf<Int>()
    while (breadthFirstQueue.isNotEmpty()) {
        visited.add(breadthFirstQueue.pollFirst()!!)
    }
    println(visited.joinToString(","))
}
