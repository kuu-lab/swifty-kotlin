// KUU-2752: java.util.Stack (and the identical LinkedList stub defect) printed
// "<object 0x...>" instead of the AbstractCollection-style "[e1, e2]" contents
// that JVM renders. Covers println, string interpolation, explicit toString(),
// Any-erased dispatch, nesting, empty, and self-reference.
import java.util.LinkedList
import java.util.Stack

fun main() {
    val stack = Stack<String>()
    stack.push("3")
    stack.push("4")
    println("stack = $stack")
    println(stack)
    println(stack.toString())

    val ints = Stack<Int>()
    ints.push(1)
    ints.push(2)
    println(ints)
    println(Stack<String>())

    val erased: Any = stack
    println(erased)
    println(listOf(stack))
    println(mapOf("k" to stack))

    val selfRef = Stack<Any>()
    selfRef.push(selfRef)
    println(selfRef)

    val linked = LinkedList<Int>()
    linked.add(1)
    linked.add(2)
    println(linked)
    println("$linked")
    val linkedErased: Any = linked
    println(linkedErased)
    val linkedSelfRef = LinkedList<Any>()
    linkedSelfRef.add(linkedSelfRef)
    println(linkedSelfRef)

    val nullable = Stack<String?>()
    nullable.push(null)
    nullable.push("tail")
    println(nullable)

    val nested = LinkedList<Stack<String>>()
    nested.add(stack)
    println(nested)
}
