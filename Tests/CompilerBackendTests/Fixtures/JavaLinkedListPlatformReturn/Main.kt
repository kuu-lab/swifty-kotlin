import structures.Stack2
fun main() {
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
    try { stack.peek(); error("missing empty peek exception") }
    catch (e: IllegalArgumentException) { println("peek:${e.message}") }
    try { stack.pop(); error("missing empty pop exception") }
    catch (e: IllegalArgumentException) { println("pop:${e.message}") }
    val nullable = Stack2<String?>()
    nullable.push(null)
    check(nullable.peek() == null)
    check(nullable.size == 1)
    check(nullable.pop() == null)
    println("stack:${stack.isEmpty}:${stack.size}")
}
