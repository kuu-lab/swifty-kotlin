fun main() {
    val map: Map<String, Int?> = mapOf("present" to null, "number" to 7)
    println(map["present"])
    println(map["missing"])
    println(map.getOrElse("present") { 11 })
    println(map.getOrElse("missing") { 13 })
    println(map.getValue("present"))

    var defaultCalls = 0
    val withNullDefault = map.withDefault {
        defaultCalls += 1
        null
    }
    println(withNullDefault.getValue("missing"))
    println(defaultCalls)

    try {
        map.getValue("missing")
    } catch (error: NoSuchElementException) {
        println(error.message)
    }

    val delegateMap: Map<String, Int> = mapOf("delegatedValue" to 42)
    val delegatedValue: Int by delegateMap
    println(delegatedValue)
}
