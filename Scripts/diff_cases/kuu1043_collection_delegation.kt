object SharedArrayList : MutableList<Any> by mutableListOf()
object SharedSet : MutableSet<Int> by mutableSetOf(2, 4)
object SharedMap : MutableMap<String, Int> by mutableMapOf("one" to 1)
class ListWrapper<T>(delegate: MutableList<T>) : MutableList<T> by delegate
class ReadOnlyList(delegate: List<Int>) : List<Int> by delegate
class SetWrapper(delegate: Set<Int>) : Set<Int> by delegate

fun main() {
    println(SharedArrayList.size)
    SharedArrayList.add("one")
    SharedArrayList.add(2)
    println(SharedArrayList.size)
    println(SharedArrayList[0])
    println(SharedArrayList.contains(2))
    println(SharedArrayList.containsAll(listOf("one", 2)))
    val shared: MutableList<Any> = SharedArrayList
    println(shared.add("three"))
    println(shared.size)
    println(shared.iterator().next())
    println(shared.removeAt(1))
    println(shared.size)

    val backing = mutableListOf(10, 20)
    val wrapper = ListWrapper(backing)
    println(wrapper[1])
    println(wrapper.add(30))
    val asList: MutableList<Int> = wrapper
    println(asList.size)
    println(asList.set(0, 11))
    println(backing[0])
    val readOnly: List<Int> = ReadOnlyList(listOf(3, 5))
    println(readOnly.size)
    println(readOnly[1])
    println(readOnly.contains(3))

    println(SharedSet.size)
    val asSet: MutableSet<Int> = SharedSet
    println(asSet.add(6))
    println(asSet.contains(6))
    println(SharedSet.remove(2))
    println(SharedSet.size)
    val readOnlySet: Set<Int> = SetWrapper(setOf(8, 9))
    println(readOnlySet.size)
    println(readOnlySet.contains(9))

    println(SharedMap.size)
    val asMap: MutableMap<String, Int> = SharedMap
    asMap["two"] = 2
    println(asMap["two"])
    println(SharedMap.containsKey("one"))
    println(SharedMap.size)
}
