class Holder {
    fun read() = M.read()

    object M {
        val number = 5
        val label = "ready"
        var count = 3
        init { println("M init") }
        fun read() = label + ":" + number + ":" + count
    }
}

object Outer {
    init { println("Outer init") }
    fun read() = N.n
    object N {
        val n = 7
        init { println("N init") }
    }
}

class Layers {
    class Middle {
        object Deep {
            val value = 9
            init { println("Deep init") }
        }
    }
}

class Constants {
    object Values {
        const val C = 11
        val value = 12
        init { println("Values init") }
    }
}

class Unused {
    object Never {
        init { println("unused init") }
    }
}

fun main() {
    println(Constants.Values.C)
    println("before non-const")
    println(Holder().read())
    Holder.M.count += 1
    println(Holder.M.read())
    println(Holder.M === Holder.M)
    println(Outer.N.n)
    println(Outer.read())
    println(Layers.Middle.Deep.value)
    println(Layers.Middle.Deep.value)
    println(Constants.Values.value)
    println(Constants.Values.C)
    println(Constants.Values.value)
}
