enum class Choice { FIRST, SECOND }
data class Box(val value: Int)

fun main() {
    val choice: Choice? = Choice.FIRST
    val absent: Choice? = null
    println(choice == Choice.FIRST)
    println((choice as Any) == 0)
    println(choice == Choice.FIRST)
    println(Choice.FIRST == choice)
    println(choice == Choice.SECOND)
    println(choice == choice)
    println(choice == absent)
    println(choice == (Choice.FIRST as Any))
    println(choice == (0 as Any))

    val number: Int? = 7
    number as Any
    println(number == 7)
    val text: String? = "text"
    text as Any
    println(text == "text")
    val box: Box? = Box(4)
    box as Any
    println(box == Box(4))
}
