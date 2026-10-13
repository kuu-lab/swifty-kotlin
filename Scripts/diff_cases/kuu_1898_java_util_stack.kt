import java.util.EmptyStackException
import java.util.Stack

private fun resolveLocalDepth(scopes: Stack<MutableMap<String, Boolean>>, name: String): Int {
    for (i in (scopes.size - 1) downTo 0) {
        if (scopes[i].containsKey(name)) return scopes.size - 1 - i
    }
    return -1
}

fun main() {
    val stack = Stack<String>()
    check(stack.push("a") == "a")
    stack.push("b")
    println(stack.pop())
    println(stack.peek())
    println(stack.size)
    println(stack.isEmpty())
    println(stack.pop())
    println(stack.isEmpty())

    val empty = Stack<String>()
    try {
        empty.pop()
        println("pop:missing")
    } catch (_: EmptyStackException) {
        println("pop:empty")
    }
    try {
        empty.peek()
        println("peek:missing")
    } catch (_: EmptyStackException) {
        println("peek:empty")
    }

    val scopes = Stack<MutableMap<String, Boolean>>()
    scopes.push(mutableMapOf("root" to true))
    scopes.push(mutableMapOf("parent" to true))
    scopes.push(mutableMapOf("current" to true))
    println(resolveLocalDepth(scopes, "root"))
    println(resolveLocalDepth(scopes, "parent"))
    println(resolveLocalDepth(scopes, "current"))
}
