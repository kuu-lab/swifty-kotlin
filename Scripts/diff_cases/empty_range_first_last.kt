fun main() {
    println((1..4).first())
    println((1..4).last())
    println((1..0).first)
    println((1..0).last)

    try {
        println((1..0).first())
    } catch (e: NoSuchElementException) {
        println("empty-first")
    }
    try {
        println((1..0).last())
    } catch (e: NoSuchElementException) {
        println("empty-last")
    }
    try {
        println((0 until 0).first())
    } catch (e: NoSuchElementException) {
        println("until-first")
    }

    println((1..0).firstOrNull())
    println((1..0).lastOrNull())
}
