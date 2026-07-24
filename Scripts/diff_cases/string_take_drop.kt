fun main() {
    // take basic cases
    println("hello".take(2))
    println("hello".take(0))
    println("hello".take(5))
    println("hello".take(100))
    println("".take(3))

    // takeLast basic cases
    println("hello".takeLast(2))
    println("hello".takeLast(0))
    println("hello".takeLast(5))
    println("hello".takeLast(100))
    println("".takeLast(3))

    // drop basic cases
    println("hello".drop(2) + "|")
    println("hello".drop(0) + "|")
    println("hello".drop(5) + "|")
    println("hello".drop(100) + "|")
    println("".drop(3) + "|")

    // dropLast basic cases
    println("hello".dropLast(2) + "|")
    println("hello".dropLast(0) + "|")
    println("hello".dropLast(5) + "|")
    println("hello".dropLast(100) + "|")
    println("".dropLast(3) + "|")

    // negative count throws IllegalArgumentException
    try {
        "hello".take(-1)
    } catch (e: IllegalArgumentException) {
        println("take negative iae")
    }
    try {
        "hello".takeLast(-1)
    } catch (e: IllegalArgumentException) {
        println("takeLast negative iae")
    }
    try {
        "hello".drop(-1)
    } catch (e: IllegalArgumentException) {
        println("drop negative iae")
    }
    try {
        "hello".dropLast(-1)
    } catch (e: IllegalArgumentException) {
        println("dropLast negative iae")
    }

    // BMP Unicode (each character is a single UTF-16 code unit)
    val u = "こんにちは"
    println(u.take(2))
    println(u.takeLast(2))
    println(u.drop(2) + "|")
    println(u.dropLast(2) + "|")

    // takeWhile: all / none / partial
    println("aaabbb".takeWhile { it == 'a' } + "|")
    println("aaabbb".takeWhile { it == 'z' } + "|")
    println("aaaaaa".takeWhile { it == 'a' } + "|")
    println("".takeWhile { it == 'a' } + "|")

    // dropWhile: all / none / partial
    println("aaabbb".dropWhile { it == 'a' } + "|")
    println("aaabbb".dropWhile { it == 'z' } + "|")
    println("aaaaaa".dropWhile { it == 'a' } + "|")
    println("".dropWhile { it == 'a' } + "|")

    // takeLastWhile: all / none / partial
    println("aaabbb".takeLastWhile { it == 'b' } + "|")
    println("aaabbb".takeLastWhile { it == 'z' } + "|")
    println("bbbbbb".takeLastWhile { it == 'b' } + "|")
    println("".takeLastWhile { it == 'b' } + "|")

    // chaining
    println("hello world".drop(6).take(3))
    println("  trimmed  ".takeWhile { it == ' ' }.length)
}
