// Function parameter type
fun processList(list: LinkedList<String>) {
    println(list.size)
}

// Return type
fun createList(): LinkedList<Int> {
    return LinkedList<Int>()
}

// Property type
class Container {
    val items: LinkedList<String> = LinkedList<String>()
    val numbers: LinkedList<Int> = LinkedList<Int>()
}

// Generic type argument
fun nestedLists() {
    val nested: LinkedList<LinkedList<String>> = LinkedList<LinkedList<String>>()
    val inner = LinkedList<String>()
    inner.add("nested")
    nested.add(inner)
    println(nested.size)
}

// Inheritance
class MyList : LinkedList<String>() {
    fun customOp() = "custom"
}

// Type constraint
fun <T : LinkedList<String>> constrain(list: T): T {
    return list
}

// Extension function on LinkedList
fun LinkedList<String>.customExtension(): String {
    return "extended: ${this.size}"
}

fun main() {
    val list: LinkedList<String> = LinkedList<String>()
    list.add("hello")
    list.add("world")
    println(list.size)
    println(list[0])

    val ml: MutableList<String> = list
    ml.add("!")
    println(ml.size)

    val nums = LinkedList<Int>()
    nums.add(1)
    nums.add(2)
    nums.add(3)
    nums.removeAt(0)
    println(nums)

    val items: List<String> = LinkedList<String>()
    println(items.size)

    // Test function parameter
    processList(list)

    // Test return type
    val created = createList()
    created.add(42)
    println(created.size)

    // Test property type
    val container = Container()
    container.items.add("property")
    println(container.items.size)

    // Test nested generic
    nestedLists()

    // Test inheritance
    val myList = MyList()
    myList.add("inherited")
    println(myList.customOp())

    // Test type constraint
    val constrained = constrain(list)
    println(constrained.size)

    // Test extension function
    println(list.customExtension())
}
