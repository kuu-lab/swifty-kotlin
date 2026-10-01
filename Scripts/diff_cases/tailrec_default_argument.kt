tailrec fun down(n: Int, step: Int = 1): Int {
    if (n <= 0) return n
    return down(n - step)
}

// A default that reads an earlier parameter must see the *new* value of it.
tailrec fun twice(n: Int, a: Int = 0, b: Int = a * 2): Int {
    if (n == 0) return a + b
    return twice(n - 1, a + 1)
}

fun main() {
    println(down(10_000_000))
    println(twice(3_000_000))
}
