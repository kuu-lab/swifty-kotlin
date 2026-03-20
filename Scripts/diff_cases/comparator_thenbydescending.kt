fun main() {
    // Basic thenByDescending: primary ascending by length, secondary descending by natural order
    println("-- thenByDescending basic --")
    val words = listOf("banana", "cherry", "fig", "apple", "date", "bat")
    val cmp1 = compareBy<String> { it.length }.thenByDescending { it }
    val sorted1 = words.sortedWith(cmp1)
    for (w in sorted1) {
        println(w)
    }

    // thenByDescending with explicit Comparable selector
    println("-- thenByDescending selector --")
    data class Person(val name: String, val age: Int)
    val people = listOf(
        Person("Alice", 30),
        Person("Bob", 25),
        Person("Charlie", 30),
        Person("Dave", 25),
        Person("Eve", 30)
    )
    val cmp2 = compareBy<Person> { it.age }.thenByDescending { it.name }
    val sorted2 = people.sortedWith(cmp2)
    for (p in sorted2) {
        println("${p.name} ${p.age}")
    }

    // Chaining multiple thenByDescending
    println("-- chained thenByDescending --")
    data class Item(val category: Int, val priority: Int, val name: String)
    val items = listOf(
        Item(1, 3, "A"),
        Item(2, 1, "B"),
        Item(1, 3, "C"),
        Item(2, 2, "D"),
        Item(1, 1, "E"),
        Item(2, 1, "F")
    )
    val cmp3 = compareBy<Item> { it.category }
        .thenByDescending { it.priority }
        .thenByDescending { it.name }
    val sorted3 = items.sortedWith(cmp3)
    for (item in sorted3) {
        println("${item.category} ${item.priority} ${item.name}")
    }

    // thenByDescending after compareByDescending
    println("-- compareByDescending then thenByDescending --")
    val cmp4 = compareByDescending<Person> { it.age }.thenByDescending { it.name }
    val sorted4 = people.sortedWith(cmp4)
    for (p in sorted4) {
        println("${p.name} ${p.age}")
    }

    // thenByDescending with Int selector
    println("-- thenByDescending int selector --")
    val cmp5 = compareBy<Person> { it.name }.thenByDescending { it.age }
    val sorted5 = people.sortedWith(cmp5)
    for (p in sorted5) {
        println("${p.name} ${p.age}")
    }

    // thenByDescending on already-equal elements (stability check)
    println("-- stability check --")
    val nums = listOf(3, 1, 4, 1, 5, 9, 2, 6, 5, 3)
    val cmp6 = compareBy<Int> { it % 2 }.thenByDescending { it }
    val sorted6 = nums.sortedWith(cmp6)
    println(sorted6)

    // thenByDescending with single element
    println("-- single element --")
    val single = listOf("only")
    println(single.sortedWith(compareBy<String> { it.length }.thenByDescending { it }))

    // thenByDescending with empty list
    println("-- empty list --")
    val empty = emptyList<String>()
    println(empty.sortedWith(compareBy<String> { it.length }.thenByDescending { it }))

    // Mix of thenBy and thenByDescending
    println("-- mix thenBy and thenByDescending --")
    val cmp7 = compareBy<Item> { it.category }
        .thenBy { it.priority }
        .thenByDescending { it.name }
    val sorted7 = items.sortedWith(cmp7)
    for (item in sorted7) {
        println("${item.category} ${item.priority} ${item.name}")
    }
}
