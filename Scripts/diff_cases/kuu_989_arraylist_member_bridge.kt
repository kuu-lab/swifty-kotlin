fun main() {
    val list = ArrayList<Int>()
    list.add(1)
    println(list)
    println(list.toString())
    println(list.isEmpty())

    try {
        list.clear()
        println(list.isEmpty())
        println(list.toString())
    } catch (e: Exception) {
        println("unexpected exception")
    }

    try {
        println(list[0])
        println("missing exception")
    } catch (e: IndexOutOfBoundsException) {
        println("out of bounds")
    }

    list.add(2)
    println(list[0])
    println(list)
    list.clear()
    println(list.isEmpty())
}
