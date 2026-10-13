fun main() {
    println({ 42 }())
    val l = { 10 }
    println(l())
    println(true && { 1; true }())
    println(false || { 1; false }())
    println((fun() = 5)())
    println({ 5 }() + { 6 }())
    println({ x: Int -> x * 3 }(4))
    val t: () -> Int = { 7 }
    println(t())
}
