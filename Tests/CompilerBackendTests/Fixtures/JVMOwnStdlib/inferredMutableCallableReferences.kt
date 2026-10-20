fun zero(): Int = 42
fun add(value: Int): Int = value + 1
fun subtract(value: Int): Int = value - 1
class Counter(val seed: Int) { fun add(value: Int): Int = seed + value }
fun main() {
    var same = ::zero
    same = ::zero
    println(same())
    var changing = ::add
    val original = changing
    changing = ::subtract
    println(changing.invoke(7))
    println(changing(7))
    println(original(7))
    var captured = ::add
    val change = { captured = ::subtract }
    change()
    println(captured(7))
    var bound = Counter(1)::add
    bound = Counter(2)::add
    println(bound(7))
    var typed: (Int) -> Int = ::add
    typed = ::subtract
    println(typed(7))
    var lambda = { value: Int -> value + 1 }
    lambda = { value: Int -> value - 1 }
    println(lambda(7))
    val branch = if (true) ::add else ::subtract
    println(branch(7))
}
