fun main() {
    val text = StringBuilder("A\uD83D\uDE00B")
    val buffer = charArrayOf('_', '_', '_', '_')
    text.getChars(1, 3, buffer, 1)
    println(buffer.concatToString())
    val splitUnits = charArrayOf('_', '_')
    text.getChars(1, 2, splitUnits, 0)
    text.getChars(2, 3, splitUnits, 1)
    println("utf16:${splitUnits[0].code},${splitUnits[1].code}")
    text.getChars(4, 4, buffer, 4)
    println(buffer.concatToString())

    fun invalid(name: String, from: Int, to: Int, destination: Int) {
        try {
            text.getChars(from, to, buffer, destination)
            println("$name:accepted")
        } catch (error: StringIndexOutOfBoundsException) {
            println("$name:string")
        } catch (error: IndexOutOfBoundsException) {
            println("$name:index")
        }
    }
    invalid("from", -1, 1, 0)
    invalid("sourceBeforeDestination", -1, 1, -1)
    invalid("reversed", 3, 1, 0)
    invalid("end", 0, 5, 0)
    invalid("maxSource", Int.MAX_VALUE, Int.MAX_VALUE, 0)
    invalid("destination", 0, 2, 3)
    invalid("negativeDestination", 0, 1, -1)
    invalid("minDestination", 0, 1, Int.MIN_VALUE)
    invalid("largeDestination", 0, 1, Int.MAX_VALUE)
    invalid("emptyOutside", 4, 4, 5)
    println(buffer.concatToString())

    val absent: CharArray? = null
    try {
        text.getChars(0, 1, absent, 0)
        println("null:accepted")
    } catch (error: NullPointerException) {
        println("null:rejected")
    }
    try {
        text.getChars(4, 4, absent, -1)
        println("nullBeforeDestination:accepted")
    } catch (error: NullPointerException) {
        println("nullBeforeDestination:null")
    }
    try {
        text.getChars(-1, 1, absent, 0)
        println("sourceBeforeNull:accepted")
    } catch (error: StringIndexOutOfBoundsException) {
        println("sourceBeforeNull:string")
    }
}
