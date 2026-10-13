/*
 * KUU-2013: nullable, non-destructive LinkedList tail access.
 * Upstream Stack2.kt: https://github.com/DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns/blob/1f89f062a056e24cc289ffdd0c6e23cadf8df887/src/main/kotlin/structures/Stack2.kt
 * Upstream Stack2Test.kt: https://github.com/DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns/blob/1f89f062a056e24cc289ffdd0c6e23cadf8df887/src/test/kotlin/structures/Stack2Test.kt
 * The first four output lines preserve the issue's exact minimal reproducer.
 * Stack2 below preserves the upstream operations, with peek returning T? to
 * express the native nullable API rather than Java's platform return type.
 * KUU-2022 tracks the unchanged upstream platform-type return compatibility.
 */

import java.util.LinkedList

private class Stack2<T> {
    private val data = LinkedList<T>()

    val isEmpty: Boolean
        get() = data.size == 0

    val size: Int
        get() = data.size

    fun push(item: T) {
        data.add(item)
    }

    fun pop(): T {
        if (isEmpty) throw IllegalArgumentException("Stack is empty!")
        return data.removeLast()
    }

    fun peek(): T? {
        if (isEmpty) throw IllegalArgumentException("Stack is empty!")
        return data.peekLast()
    }

    fun clear() {
        data.clear()
    }
}

fun main() {
    val q=LinkedList<String>(); println(q.peekLast()); q.add("a"); q.add("b"); println(q.peekLast()); println(q.size); q.clear(); println(q.peekLast())

    val strings = LinkedList<String>()
    val emptyString: String? = strings.peekLast()
    println("string-empty:$emptyString:${strings.size}")
    strings.add("head")
    val singleString: String? = strings.peekLast()
    println("string-single:$singleString:${strings.size}")
    strings.add("tail")
    val tailString: String? = strings.peekLast()
    println("string-tail:${tailString?.length}:${strings.peekLast()}:${strings.size}:${strings.first}")
    println("string-pop:${strings.removeLast()}:${strings.peekLast()}:${strings.size}")
    strings.clear()
    println("string-clear:${strings.peekLast()}:${strings.size}")

    val ints = LinkedList<Int>()
    val emptyInt: Int? = ints.peekLast()
    println("int-empty:$emptyInt:${ints.size}")
    ints.add(7)
    val singleInt: Int? = ints.peekLast()
    println("int-single:${singleInt!! + 1}:${ints.size}")
    ints.add(42)
    val tailInt: Int? = ints.peekLast()
    println("int-tail:${tailInt!! + 1}:${ints.peekLast()}:${ints.size}:${ints.first}")
    println("int-pop:${ints.removeLast()}:${ints.peekLast()}:${ints.size}")
    ints.clear()
    println("int-clear:${ints.peekLast()}:${ints.size}")

    val nullableInts = LinkedList<Int?>()
    println("nullable-int-empty:${nullableInts.peekLast()}:${nullableInts.size}")
    nullableInts.add(null)
    println("nullable-int-single:${nullableInts.peekLast()}:${nullableInts.size}")
    nullableInts.add(9)
    val nullableIntTail: Int? = nullableInts.peekLast()
    println("nullable-int-value:${nullableIntTail!! + 1}:${nullableInts.size}")
    nullableInts.add(null)
    println("nullable-int-tail:${nullableInts.peekLast()}:${nullableInts.peekLast()}:${nullableInts.size}")
    println("nullable-int-pop:${nullableInts.removeLast()}:${nullableInts.peekLast()}:${nullableInts.size}")
    nullableInts.clear()
    println("nullable-int-clear:${nullableInts.peekLast()}:${nullableInts.size}")

    val nullableStrings = LinkedList<String?>()
    println("nullable-string-empty:${nullableStrings.peekLast()}:${nullableStrings.size}")
    nullableStrings.add("a")
    val nullableStringTail: String? = nullableStrings.peekLast()
    println("nullable-string-single:${nullableStringTail?.length}:${nullableStrings.size}")
    nullableStrings.add(null)
    println("nullable-string-tail:${nullableStrings.peekLast()}:${nullableStrings.peekLast()}:${nullableStrings.size}:${nullableStrings.first}")
    nullableStrings.clear()
    println("nullable-string-clear:${nullableStrings.peekLast()}:${nullableStrings.size}")

    // Preserve Stack2Test's push/pop/peek/clear assertions and check empty guards.
    val stack = Stack2<Int>()
    stack.push(1)
    stack.push(2)
    stack.push(3)
    check(!stack.isEmpty)
    check(stack.size == 3)
    check(stack.pop() == 3)
    check(stack.pop() == 2)
    check(stack.pop() == 1)
    check(stack.isEmpty)
    check(stack.size == 0)
    stack.push(10)
    stack.push(20)
    stack.push(30)
    check(stack.size == 3)
    check(stack.peek() == 30)
    check(stack.peek() == 30)
    check(stack.size == 3)
    stack.clear()
    check(stack.isEmpty)
    check(stack.size == 0)
    try {
        stack.peek()
        error("Empty peek must throw")
    } catch (exception: IllegalArgumentException) {
        println("stack-peek:${exception.message}")
    }
    try {
        stack.pop()
        error("Empty pop must throw")
    } catch (exception: IllegalArgumentException) {
        println("stack-pop:${exception.message}")
    }
    println("stack:${stack.isEmpty}:${stack.size}")
}
