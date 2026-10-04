fun main() {
    val range = 1..10
    println(range.take(3))   // [1, 2, 3]
    println(range.drop(7))   // [8, 9, 10]
    println(range.take(0))   // []
    println(range.drop(20))  // []
    println((1..5).average())  // 3.0
    println((1..5).sorted())   // [1, 2, 3, 4, 5]

    try {
        (1..5).take(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1..5).drop(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1L..5L).take(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1L..5L).drop(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1u..5u).take(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        (1u..5u).drop(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        ('a'..'e').take(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        ('a'..'e').drop(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
