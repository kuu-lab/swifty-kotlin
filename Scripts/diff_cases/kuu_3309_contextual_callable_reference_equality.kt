// SKIP-DIFF (DEBT-DIFF-001): kotlinc 2.4.20 rejects callable references to context-parameter functions.
import kotlin.ExperimentalContextParameters

@OptIn(ExperimentalContextParameters::class)
context(a: String, b: Int)
fun foo(): String = "$a$b"

object O {
    @OptIn(ExperimentalContextParameters::class)
    context(a: String, b: Int)
    fun bar(): String = "$a$b"
}

@OptIn(ExperimentalContextParameters::class)
fun main() {
    val r1: () -> String = context("A", 1) { ::foo }
    val r2: () -> String = context("A", 1) { ::foo }
    val different: () -> String = context("B", 1) { ::foo }
    val o1: () -> String = context("A", 1) { O::bar }
    val o2: () -> String = context("A", 1) { O::bar }
    val differentObjectReference: () -> String = context("B", 1) { O::bar }

    println(r1 == r2)
    println(r1.hashCode() == r2.hashCode())
    println(r1 == different)
    println(r1())
    println(o1 == o2)
    println(o1.hashCode() == o2.hashCode())
    println(o1 == differentObjectReference)
    println(o1())
}
