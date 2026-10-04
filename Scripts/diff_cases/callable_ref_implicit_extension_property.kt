package probes.references

val Int.lastDigit: Int get() = this % 10

class Counter(var value: Int)
var Counter.twice: Int
    get() = value * 2
    set(newValue) { value = newValue / 2 }

fun main() {
    val direct = with(37) { ::lastDigit }
    println(direct.get())
    val outer = with(48) { with("s") { ::lastDigit } }
    println(outer.get())
    val delayed = with(59) { with("s") { { ::lastDigit } } }
    println(delayed().get())
    val nearest = with(37) { with(24) { ::lastDigit } }
    println(nearest.get())
    val stringLength = with("abcd") { ::length }
    println(stringLength.get())
    val counter = Counter(6)
    val mutable = with(counter) { with("s") { ::twice } }
    println(mutable.get())
    mutable.set(30)
    println(counter.value)
}
