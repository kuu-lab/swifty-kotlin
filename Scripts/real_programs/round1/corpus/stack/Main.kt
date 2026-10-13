import structures.*
fun main() {
    val stack = Stack1<String>()
    stack.push("a")
    stack.push("b")
    println(stack.peek())
    println(stack.pop())
    println(stack.pop())
    println(stack.isEmpty)
}
