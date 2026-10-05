fun main() {
    val list = ArrayList<Int>()
    list.trimToSize()
    list.ensureCapacity(-1)
    list.add(10)
    list.add(20)
    for (capacity in listOf(Int.MIN_VALUE, -1, 0, 1, 2, 8, 1024)) {
        list.ensureCapacity(capacity)
        list.trimToSize()
        println(list.size)
        println(list[0])
        println(list[1])
    }
    list.add(30)
    println(list.size)
    println(list[2])
    list.removeAt(0)
    list.trimToSize()
    println(list.size)
    println(list[0])
}
