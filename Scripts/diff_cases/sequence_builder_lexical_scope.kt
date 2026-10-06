fun main() {
    println(sequence { for (value in 0 until 3) yield(value) }.count())
    println(sequence<Int> { for (value in 0 until 3) yield(value) }.count())

    val value = "outer"
    println(sequence { for (value in 0..2) yield(value) }.toList())
    println(sequence { val value = 7; yield(value) }.first())
    println(sequence {
        for (value in listOf(1, 2)) yieldAll(listOf(value))
    }.toList())
    println(sequence {
        for (value in 0 until 2) {
            for (value in 2 until 3) yield(value)
        }
    }.toList())
    println(iterator { for (value in 0 until 3) yield(value) }.next())
    println(iterator<Int> { val value = 7; yield(value) }.next())
    println(sequence { for (value in 'a'..'c') yield(value) }.toList())
    println(sequence { val value: Int? = null; yield(value) }.first())
    println(value)
}
