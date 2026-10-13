import com.ginsberg.advent2023.*
fun main() {
    val first = """
            1abc2
            pqr3stu8vwx
            a1b2c3d4e5f
            treb7uchet
        """.trimIndent().lines()
    val second = """
            two1nine
            eightwothree
            abcone2threexyz
            xtwone3four
            4nineeightseven2
            zoneight234
            7pqrstsixteen
        """.trimIndent().lines()
    println(Day01(first).solvePart1())
    println(Day01(second).solvePart2())
}
