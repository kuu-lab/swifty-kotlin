package probe

import probe.Obj.f
import kotlin.Result.Companion.failure

object Obj {
    fun f(x: Int): Int = x + 1
}

fun useResult(): Result<Int> {
    val g: (Throwable) -> Result<Int> = ::failure
    return g(RuntimeException("x"))
}

fun applyFailure(block: (Throwable) -> Result<Int>): Result<Int> = block(IllegalStateException("y"))

fun main() {
    val fr: (Int) -> Int = ::f
    println(fr(40))
    println(useResult().isFailure)
    println(applyFailure(::failure).isFailure)
}
