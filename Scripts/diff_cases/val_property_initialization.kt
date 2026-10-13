class InitValue(flag: Boolean) {
    val value: Int
    init {
        if (flag) this.value = 1 else value = 2
    }
}

class MultipleInit {
    val first: Int
    val second: Int
    init { first = 3 }
    init { this.second = 4 }
}

class Secondary {
    val value: Int
    constructor() : this(5)
    constructor(value: Int) { this.value = value }
    constructor(flag: Boolean) { if (flag) value = 6 else this.value = 7 }
}

class Primary() {
    val value: Int
    init { value = 8 }
    constructor(ignored: Int) : this()
}

fun main() {
    println(InitValue(true).value)
    println(InitValue(false).value)
    println(MultipleInit().first)
    println(MultipleInit().second)
    println(Secondary().value)
    println(Secondary(true).value)
    println(Secondary(false).value)
    println(Primary(0).value)
}
