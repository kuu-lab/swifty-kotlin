fun main() {
    var sum = 0L
    var count = 0
    for (i in Int.MAX_VALUE - 2..Int.MAX_VALUE) {
        if (i == Int.MAX_VALUE - 1) continue
        sum += i
        count++
    }
    println(sum)
    println(count)

    var single = 0
    for (i in Int.MAX_VALUE..Int.MAX_VALUE) {
        single++
    }
    println(single)

    var empty = 0
    for (i in Int.MAX_VALUE..Int.MIN_VALUE) {
        empty++
    }
    println(empty)

    val typed: IntRange = Int.MAX_VALUE - 1..Int.MAX_VALUE
    var typedSum = 0L
    for (i in typed) {
        typedSum += i
    }
    println(typedSum)
}
