fun roundTrip(value: Any?): Int = value as Int

fun main() {
    var index = 0
    var checksum = 0
    while (index < 10_000) {
        checksum += roundTrip(index)
        index++
    }
    println(checksum)
}
