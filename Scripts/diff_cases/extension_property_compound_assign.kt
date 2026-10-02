class Box {
    var x: Int = 0
    var reads: Int = 0
    var writes: Int = 0
}

var Box.y: Int
    get() {
        reads++
        return x
    }
    set(v) {
        writes++
        x = v
    }

var receiverCalls = 0
fun receiver(b: Box): Box {
    receiverCalls++
    return b
}

class CounterValue(val n: Int) {
    operator fun plus(x: Int): CounterValue = CounterValue(n + x)
    operator fun inc(): CounterValue = CounterValue(n + 1)
    operator fun dec(): CounterValue = CounterValue(n - 1)
}

class NumberBox(var item: CounterValue)
var NumberBox.y: CounterValue
    get() = item
    set(v) { item = v }

class Accumulator {
    var n: Int = 0
    operator fun plusAssign(x: Int) { n += x }
}

class AccumulatorBox(val item: Accumulator)
val AccumulatorBox.y: Accumulator get() = item

class MemberBox { var y: Int = 10 }
var MemberBox.y: Int
    get() = 100
    set(v) { println("extension setter $v") }

fun main() {
    val b = Box()
    b.y = 5
    b.y += 2
    println(b.x)
    println(receiver(b).y++)
    println(++receiver(b).y)
    println(receiver(b).y--)
    println(--receiver(b).y)
    b.y -= 3
    b.y *= 4
    b.y /= 2
    b.y %= 3
    println(b.x)
    println(b.reads)
    println(b.writes)
    println(receiverCalls)

    val numbers = NumberBox(CounterValue(10))
    numbers.y += 5
    println(numbers.y.n)
    println(numbers.y++.n)
    println((++numbers.y).n)
    println(numbers.y--.n)
    println((--numbers.y).n)
    println(numbers.y.n)

    val accumulator = AccumulatorBox(Accumulator())
    accumulator.y += 3
    println(accumulator.y.n)

    val member = MemberBox()
    member.y += 2
    println(member.y++)
    println(member.y)
}
