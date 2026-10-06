fun main() {
    println(255.toString(16))
    println((-255).toString(16))
    println(0.toString(16))
    println(Int.MIN_VALUE.toString(10))
    println(Int.MIN_VALUE.toString(2))
    println(Int.MAX_VALUE.toString(36))
    println(1.toString(2))
    println((-1).toString(2))

    println(255L.toString(16))
    println((-255L).toString(16))
    println(0L.toString(16))
    println(Long.MIN_VALUE.toString(10))
    println(Long.MIN_VALUE.toString(2))
    println(Long.MAX_VALUE.toString(36))

    try {
        1.toString(1)
        println("no-throw")
    } catch (e: IllegalArgumentException) {
        println("toString-invalid-radix")
    }

    try {
        1.toString(37)
        println("no-throw")
    } catch (e: IllegalArgumentException) {
        println("toString-invalid-radix")
    }

    try {
        1L.toString(1)
        println("no-throw")
    } catch (e: IllegalArgumentException) {
        println("toString-invalid-radix-long")
    }

    try {
        1L.toString(37)
        println("no-throw")
    } catch (e: IllegalArgumentException) {
        println("toString-invalid-radix-long")
    }
}
