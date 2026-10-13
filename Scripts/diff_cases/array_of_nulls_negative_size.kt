fun main() {
    try {
        arrayOfNulls<String>(-1)
        println("no throw")
    } catch (e: NegativeArraySizeException) {
        println("negative=${e.message}")
    }

    try {
        arrayOfNulls<Int>(-5)
        println("no throw")
    } catch (e: NegativeArraySizeException) {
        println("negative5=${e.message}")
    }

    println(arrayOfNulls<String>(0).size)
    println(arrayOfNulls<String>(2).size)
}
