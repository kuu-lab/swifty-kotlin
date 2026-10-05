// KUU-1179: defaults must share the enclosing mutable local's capture cell.
class Args(val x: String?)

fun memberDefault() {
    var args = Args("hello")
    class Writer { fun write(value: Unit = run { args = Args(null) }) {} }
    val writer = Writer()
    writer.write(Unit)
    println(args.x)
    writer.write()
    println(args.x)
    args = Args("again")
    writer.write()
    println(args.x)
}

fun primaryDefault() {
    var args = Args("hello")
    class Writer(value: Unit = run { args = Args(null) })
    Writer(Unit)
    println(args.x)
    Writer()
    println(args.x)
}

fun secondaryDefault() {
    var args = Args("hello")
    class Writer {
        constructor(value: Unit = kotlin.run { args = Args(null) }) {}
    }
    Writer(Unit)
    println(args.x)
    Writer()
    println(args.x)
}

fun secondaryDelegation() {
    var args = Args("hello")
    class Writer(value: Unit) {
        constructor() : this(kotlin.run { args = Args(null) })
    }
    Writer()
    println(args.x)
}

fun escapedDefault(): () -> Int {
    var count = 0
    val step = 2
    class Counter {
        fun next(value: Int = run { count = count + step; count }): Int = value
    }
    val counter = Counter()
    return { counter.next() }
}

fun nestedDefault() {
    var count = 0
    val action: () -> Unit = {
        class Counter {
            fun next(value: Int = run { count = count + 1; count }): Int = value
        }
        println(Counter().next())
    }
    action()
    action()
    println(count)
}

fun parameterShadowing() {
    val seed = 7
    class Counter(val first: Int = seed, val second: Int = first + 1) {
        fun next(seed: Int = 3, result: Int = seed + second): Int = result
    }
    val counter = Counter()
    println(counter.first)
    println(counter.second)
    println(counter.next())
    println(counter.next(5))
}

fun semicolonDefault(value: Int = run { var count = 0; count = count + 1; count }): Int = value

fun main() {
    memberDefault()
    primaryDefault()
    secondaryDefault()
    secondaryDelegation()
    val next = escapedDefault()
    println(next())
    println(next())
    nestedDefault()
    parameterShadowing()
    println(semicolonDefault())
}
