fun main() {
    val nested = arrayOf(intArrayOf(1, 2), intArrayOf(3, 4))
    for (row in nested) {
        for (v in row) {
            print("$v ")
        }
    }
    println()

    val cube = arrayOf(arrayOf(intArrayOf(1, 2), intArrayOf(3, 4)), arrayOf(intArrayOf(5, 6), intArrayOf(7, 8)))
    for (plane in cube) {
        for (row in plane) {
            for (v in row) {
                print("$v ")
            }
        }
    }
    println()

    val listOfArrays = listOf(intArrayOf(9, 10), intArrayOf(11, 12))
    for (row in listOfArrays) {
        for (v in row) {
            print("$v ")
        }
    }
    println()

    val arrayOfLists = arrayOf(listOf(13, 14), listOf(15, 16))
    for (row in arrayOfLists) {
        for (v in row) {
            print("$v ")
        }
    }
    println()
}
