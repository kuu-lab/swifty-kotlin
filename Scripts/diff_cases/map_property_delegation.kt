val topMap = mapOf("top" to 7)
val top by topMap
var topMutable by mutableMapOf("topMutable" to 8)

class MapOwner(val values: Map<String, Int>, val mutableValues: MutableMap<String, Int>) {
    val member by values
    var writable by mutableValues
}

fun main() {
    val m = mapOf("a" to 1, "b" to 2)
    val a by m
    val b: Int by m
    println(a)
    println(b)
    val explicitlyTyped: Map<String, Int> = mapOf("typed" to 3)
    val typed by explicitlyTyped
    println(typed)
    val wideKeys: Map<Any, Int> = mapOf("wide" to 4)
    val wide by wideKeys
    println(wide)
    val strings = mapOf("text" to "hello")
    val text by strings
    println(text)
    val nullableValues: Map<String, Int?> = mapOf("nullable" to null)
    val nullable by nullableValues
    println(nullable)

    val mutable = mutableMapOf("value" to 10)
    var value by mutable
    println(value)
    value = 11
    println(mutable["value"])
    mutable["value"] = 12
    println(value)
    val defaulted by emptyMap<String, Int>().withDefault { key -> key.length }
    println(defaulted)
    var inserted by mutableMapOf<String, Int>().withDefault { 20 }
    println(inserted)
    inserted = 21
    println(inserted)
    try {
        val missing by emptyMap<String, Int>()
        println(missing)
    } catch (e: NoSuchElementException) {
        println(e.message)
    }

    println(top)
    println(topMutable)
    topMutable = 9
    println(topMutable)
    val memberValues = mutableMapOf("member" to 30, "writable" to 31)
    val owner = MapOwner(memberValues, memberValues)
    println(owner.member)
    owner.writable = 32
    println(memberValues["writable"])
    memberValues["member"] = 33
    println(owner.member)
}
