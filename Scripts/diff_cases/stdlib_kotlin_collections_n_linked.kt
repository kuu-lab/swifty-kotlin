fun main() {
    val firstEmpty = linkedSetOf<String>()
    val secondEmpty = linkedSetOf<String>()
    firstEmpty.add("only-first")
    println(secondEmpty)

    val setElements = arrayOf(1, 2, 1)
    println(linkedSetOf(*setElements))
    println(linkedSetOf<String?>(null, "a", null))

    val pairs = arrayOf("x" to 3, "y" to 4, "x" to 5)
    val spreadMap = linkedMapOf(*pairs)
    println(spreadMap)
    println(linkedMapOf<String?, Int?>(null to null, "a" to 1, "a" to 2))
    println(spreadMap.keys.toList())
}
