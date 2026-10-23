// KUU-3053: java.util.Stack must expose its Java-style empty() alias.
import java.util.Stack

fun main() {
    val stack = Stack<Int>()
    println(stack.empty())
    stack.push(1)
    println(stack.empty())
    println(stack.peek())
    stack.pop()
    println(stack.empty())
}
