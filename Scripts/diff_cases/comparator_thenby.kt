fun main() {
    // --- compareBy + thenBy: multi-key sort ---
    println("-- compareBy then thenBy --")
    data class Person(val name: String, val age: Int)
    val people = listOf(
        Person("Alice", 30),
        Person("Bob", 25),
        Person("Alice", 25),
        Person("Bob", 30),
        Person("Charlie", 25)
    )

    // Sort by name ascending, then by age ascending
    val cmp1 = compareBy<Person> { it.name }.thenBy { it.age }
    val sorted1 = people.sortedWith(cmp1)
    for (p in sorted1) println("${p.name} ${p.age}")

    // --- thenByDescending ---
    println("-- thenByDescending --")
    val cmp2 = compareBy<Person> { it.name }.thenByDescending { it.age }
    val sorted2 = people.sortedWith(cmp2)
    for (p in sorted2) println("${p.name} ${p.age}")

    // --- compareByDescending + thenBy ---
    println("-- compareByDescending + thenBy --")
    val cmp3 = compareByDescending<Person> { it.name }.thenBy { it.age }
    val sorted3 = people.sortedWith(cmp3)
    for (p in sorted3) println("${p.name} ${p.age}")

    // --- reversed ---
    println("-- reversed --")
    val cmp4 = compareBy<Person> { it.name }.thenBy { it.age }.reversed()
    val sorted4 = people.sortedWith(cmp4)
    for (p in sorted4) println("${p.name} ${p.age}")

    // --- thenBy chained multiple times ---
    println("-- triple chain --")
    data class Item(val category: String, val price: Int, val name: String)
    val items = listOf(
        Item("B", 10, "Zeta"),
        Item("A", 20, "Alpha"),
        Item("A", 10, "Beta"),
        Item("B", 10, "Alpha"),
        Item("A", 10, "Alpha")
    )
    val cmp5 = compareBy<Item> { it.category }.thenBy { it.price }.thenBy { it.name }
    val sorted5 = items.sortedWith(cmp5)
    for (i in sorted5) println("${i.category} ${i.price} ${i.name}")

    // --- thenBy with integers ---
    println("-- integer sort --")
    val nums = listOf(3, 1, 4, 1, 5, 9, 2, 6)
    val cmp6 = compareBy<Int> { it % 3 }.thenBy { it }
    println(nums.sortedWith(cmp6))

    // --- compareBy + thenBy on strings ---
    println("-- string length then alpha --")
    val words = listOf("fig", "cherry", "apple", "date", "banana", "fig")
    val cmp7 = compareBy<String> { it.length }.thenBy { it }
    println(words.sortedWith(cmp7))
}
