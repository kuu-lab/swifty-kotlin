// KUU-1939: collection-family names in user packages must retain user dispatch.
package mypkg

class HashSet<T> {
    fun add(x: T): Boolean {
        println("user-add-called")
        return false
    }
}

class HashMap<K, V> {
    fun get(k: K): String = "user-HashMap.get"
}

class MutableSet<T> {
    fun add(x: T): Boolean = true
    fun marker(): String = "user-MutableSet"
}

class LinkedHashSet<T> { fun add(x: T): String = "user-LinkedHashSet.add" }
class MutableMap<K, V> { fun get(k: K): String = "user-MutableMap.get" }
class LinkedHashMap<K, V> { fun get(k: K): String = "user-LinkedHashMap.get" }

fun main() {
    val hs = HashSet<Int>()
    println(hs.add(5))
    val h = HashMap<String, Int>()
    println(h.get("x"))

    val ms = MutableSet<Int>()
    println(ms.add(3))
    println(ms.marker())
    println(ms is MutableSet<*>)

    val typedSet: HashSet<Int> = HashSet<Int>()
    println(typedSet.add(6))
    val typedMap: HashMap<String, Int> = HashMap<String, Int>()
    println(typedMap.get("y"))
    println(LinkedHashSet<Int>().add(7))
    println(MutableMap<String, Int>().get("z"))
    println(LinkedHashMap<String, Int>().get("w"))

    val stdlibSet = hashSetOf(1)
    println(stdlibSet.add(2))
    println(stdlibSet.add(1))
    val stdlibMap = hashMapOf("key" to 9)
    println(stdlibMap.get("key"))
}
