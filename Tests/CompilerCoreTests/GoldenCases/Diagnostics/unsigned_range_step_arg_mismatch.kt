package golden.diagnostics

// KUU-4126: upstream declares `step` on Long/ULong ranges and progressions
// only with a Long parameter, so unsigned step operands and non-literal Int
// steps are argument type mismatches — not "no viable overload" failures.
// The UInt lane keeps the same single-overload mismatch diagnostic.
fun ulongStepUnsignedArg() = 1uL..7uL step 2uL

fun longStepUnsignedArg() = 1L..7L step 2uL

fun uintStepUnsignedArg() = 1u..7u step 2u

fun ulongStepStringArg() = 1uL..7uL step "x"

fun ulongStepIntVariable() {
    val s: Int = 2
    println(1uL..7uL step s)
}

fun ulongStepForLoop() {
    for (i in 0uL..10uL step 2uL) {
        println(i)
    }
}
