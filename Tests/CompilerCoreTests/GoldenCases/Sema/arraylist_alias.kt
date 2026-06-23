fun processList(list: ArrayList<String>) {
    println(list.size)
}

fun createList(): ArrayList<Int> {
    return ArrayList<Int>()
}

class Container {
    val items: ArrayList<String> = ArrayList()
    val numbers: ArrayList<Int> = ArrayList<Int>()
}

fun nestedLists() {
    val nested: ArrayList<ArrayList<String>> = ArrayList()
    val inner = ArrayList<String>()
    inner.add("nested")
    nested.add(inner)
    println(nested.size)
}

class MyList : ArrayList<String>() {
    fun customOp() = "custom"
}

fun <T : ArrayList<String>> constrain(list: T): T {
    return list
}

fun ArrayList<String>.customExtension(): String {
    return "extended: ${this.size}"
}

fun main() {
    val list: ArrayList<String> = ArrayList()
    list.add("hello")
    list.add("world")
    println(list.size)
    println(list[0])

    val ml: MutableList<String> = list
    ml.add("!")
    println(ml.size)

    val nums = ArrayList<Int>()
    nums.add(1)
    nums.add(2)
    nums.add(3)
    nums.removeAt(0)
    println(nums)

    val items: List<String> = ArrayList()
    println(items.size)

    processList(list)

    val created = createList()
    created.add(42)
    println(created.size)

    val container = Container()
    container.items.add("property")
    println(container.items.size)

    nestedLists()

    val myList = MyList()
    myList.add("inherited")
    println(myList.customOp())

    val constrained = constrain(list)
    println(constrained.size)

    println(list.customExtension())
}
