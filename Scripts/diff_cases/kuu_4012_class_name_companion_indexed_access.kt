// KUU-4012: ClassName[index] resolves companion object operator fun get/set.
class K {
    companion object {
        operator fun get(i: Int) = "got$i"
    }
}
class K2 {
    companion object {
        operator fun invoke(i: Int) = "inv$i"
    }
}
enum class Month {
    JAN, FEB;
    companion object {
        operator fun get(i: Int) = "m$i"
    }
}
class Outer {
    class Nested {
        companion object {
            operator fun get(i: Int) = i * 2
        }
    }
}
class S {
    companion object {
        val items = mutableListOf("a", "b", "c")
        operator fun get(i: Int) = items[i]
        operator fun set(i: Int, v: String) {
            items[i] = v
        }
    }
}
class Both {
    operator fun get(i: Int) = "inst$i"
    companion object {
        operator fun get(i: Int) = "comp$i"
    }
}
class Counter {
    companion object {
        var value = 0
        operator fun get(i: Int) = value
        operator fun set(i: Int, v: Int) {
            value = v
        }
    }
}
fun main() {
    println(K[1])
    println(K2(2))
    println(Month[0])
    println(Outer.Nested[3])
    S[1] = "z"
    println(S[1])
    Counter[0] += 5
    println(Counter[0])
    println(Both[1])
}
