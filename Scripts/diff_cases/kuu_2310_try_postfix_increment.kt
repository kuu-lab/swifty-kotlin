var counter = 0

fun value(): Int {
    counter = 1
    return try {
        counter++
    } finally {
        counter++
    }
}

fun box() = if (value() == 1 && counter == 3) "OK" else "FAIL"

fun main() {
    print(box())
}
