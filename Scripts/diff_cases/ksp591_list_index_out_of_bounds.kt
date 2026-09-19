fun main() {
    val list = listOf(1)
    try {
        println(list[5])
    } catch (_: IndexOutOfBoundsException) {
        println("list-get")
    }

    try {
        println(list[-1])
    } catch (_: IndexOutOfBoundsException) {
        println("list-negative")
    }

    val mutable = mutableListOf(1, 2)
    try {
        println(mutable[2])
    } catch (_: IndexOutOfBoundsException) {
        println("mutable-get")
    }

    try {
        println(listOf(1, 2, 3).get(3))
    } catch (_: IndexOutOfBoundsException) {
        println("list-get-method")
    }

    try {
        println(mutable.removeAt(9))
    } catch (_: IndexOutOfBoundsException) {
        println("remove-at")
    }

    val iterator = listOf(1).iterator()
    println(iterator.next())
    try {
        println(iterator.next())
    } catch (_: NoSuchElementException) {
        println("iterator-next")
    }
}
