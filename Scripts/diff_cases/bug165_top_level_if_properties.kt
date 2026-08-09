// BUG-165 minimal repro: multiple top-level properties initialized by `if`
// expressions used to crash kswiftc during LLVM codegen because property
// initializer labels were reset and then injected into `main`, causing
// duplicate KIR labels within the same function.

val a = if (1 > 2) 1 else 2
val b = if (1 < 2) 3 else 4

fun main() {
    println(a)
    println(b)
}
