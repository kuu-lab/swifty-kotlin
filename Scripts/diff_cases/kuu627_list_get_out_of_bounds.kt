// KUU-627: List.get and ArrayList.get must throw for an out-of-range index.
fun main() {
    try {
        val list = listOf(1, 2, 3)
        println(list[5])
        println("missing-list")
    } catch (e: IndexOutOfBoundsException) {
        println("caught-list")
    }

    try {
        val arrayList = arrayListOf("x")
        println(arrayList[9])
        println("missing-array-list")
    } catch (e: IndexOutOfBoundsException) {
        println("caught-array-list")
    }
}
