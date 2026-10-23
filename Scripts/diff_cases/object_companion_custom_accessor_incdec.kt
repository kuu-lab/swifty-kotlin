object GetterOnly {
    var calls = ""
    var value: Int = 1
        get() { calls += "g"; return field }

    fun incrementTwice(): Int {
        value++
        ++value
        return value
    }
}

class CompanionAccessors {
    companion object {
        var calls = ""
        var value: Int = 1
            get() { calls += "g"; return field }
            set(newValue) { calls += "s"; field = newValue }

        fun incrementTwice(): Int {
            value++
            ++value
            return value
        }
    }
}

fun main() {
    println(GetterOnly.incrementTwice())
    println(GetterOnly.calls)
    println(CompanionAccessors.incrementTwice())
    println(CompanionAccessors.calls)
}
