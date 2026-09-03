fun main() {
    val count = 100000
    val map = mutableMapOf<Int, Int>()
    val set = mutableSetOf<Int>()

    var value = 0
    while (value < count) {
        map[value] = value * 3
        set.add(value)
        value++
    }

    var checksum = 0
    value = 0
    while (value < count) {
        if (value % 997 == 0) {
            checksum += map[value] ?: 0
            if (set.contains(value)) checksum++
        }
        value++
    }

    println(checksum)
}
