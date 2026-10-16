enum class E {
    A, B
}

// This mirrors JetBrains' enumEntryHashCode.kt box assertion.
fun box() = if (E.A.hashCode() == E.A.ordinal && E.B.hashCode() == E.B.ordinal) "FAIL" else "OK"

class Plain

class Explicit {
    override fun hashCode(): Int = 12345
}

fun main() {
    println(box())

    val firstHash = E.A.hashCode()
    val secondHash = E.B.hashCode()
    val erasedFirst: Any = E.A
    val erasedSecond: Any = E.B
    println("stable=${E.A.hashCode() == firstHash && E.B.hashCode() == secondHash}")
    println("notOrdinal=${firstHash != E.A.ordinal && secondHash != E.B.ordinal}")
    println("erased=${erasedFirst.hashCode() == firstHash && erasedSecond.hashCode() == secondHash}")

    val plain = Plain()
    val otherPlain = Plain()
    println("plainStable=${plain.hashCode() == plain.hashCode()}")
    println("plainDistinct=${plain.hashCode() != otherPlain.hashCode()}")
    println("explicit=${Explicit().hashCode()}")
}
