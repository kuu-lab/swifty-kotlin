fun capacity(value: Int): Int {
    println("capacity: $value")
    return value
}

fun main() {
    for (value in listOf(-1, Int.MIN_VALUE, 0, 4)) {
        try {
            val list = ArrayList<Int>(capacity(value))
            println("size: ${list.size}")
            list.add(7)
            println(list[0])
        } catch (e: IndexOutOfBoundsException) {
            println("wrong exception")
        } catch (e: IllegalArgumentException) {
            println("IllegalArgumentException")
        } finally {
            println("finally")
        }
    }
    val empty = ArrayList<Int>()
    println(empty is ArrayList<*>)
    val input = mutableListOf(1, 2)
    val copy = ArrayList(input)
    input.add(3)
    copy.add(4)
    println(copy.size)
    println(copy[0])
    println(copy[1])
    println(copy[2])
    println(input.size)
    println(input[2])
}
