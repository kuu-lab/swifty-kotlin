import structures.*
fun main() {
    val list = SingleLinkedList<Int>()
    list.add(2)
    list.addFirst(1)
    list.addLast(3)
    println(list.contains(2))
    println(list.remove(2))
    println(list)
    list.clear()
    println(list.isEmpty)
}
