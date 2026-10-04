class Counter(private var addend: Int) {
    fun bump(): Int {
        addend += 362437
        return addend
    }
    fun get(): Int = addend
}

class Accumulator(private var a: Int, private var b: Int) {
    fun adjust(): String {
        a += 1
        a -= 2
        a *= 3
        a /= 2
        a %= 5
        b++
        b++
        b--
        return "a=" + a + " b=" + b
    }
}

class Message(private var text: String) {
    fun append(suffix: String): String {
        text += suffix
        return text
    }
}

fun main() {
    // Compound assignment on a constructor-backed instance field must persist
    // across the method call and be visible from other methods.
    val c = Counter(43008)
    println(c.bump())
    println(c.get())

    // ++ / -- and chained compound-assign operators across multiple fields.
    val acc = Accumulator(10, 100)
    println(acc.adjust())

    // += on a String-typed instance field.
    val m = Message("a")
    println(m.append("b"))
    println(m.append("c"))
}
