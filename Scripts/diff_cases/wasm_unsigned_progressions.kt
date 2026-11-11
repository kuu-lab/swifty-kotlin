// DIFF_WASM

private fun printULongProgression(progression: ULongProgression) {
    for (value in progression) {
        println(value)
    }
}

fun main() {
    for (value in 2147483646u..2147483650u step 2) {
        println(value)
    }
    for (value in (ULong.MAX_VALUE - 4UL)..ULong.MAX_VALUE step 2L) {
        println(ULong.MAX_VALUE - value)
    }

    val range = (UInt.MAX_VALUE - 3u)..UInt.MAX_VALUE
    val uints: UIntProgression = range step 2
    for (value in uints) {
        println(value)
    }
    // A new step uses the aligned last element of the previous progression.
    for (value in uints.step(3)) {
        println(value)
    }

    val ulongs: ULongProgression = 0UL..ULong.MAX_VALUE step Long.MAX_VALUE
    printULongProgression(ulongs)
    printULongProgression(ulongs)

    for (value in UInt.MAX_VALUE..UInt.MAX_VALUE) {
        println(value)
    }
    for (value in ULong.MAX_VALUE..ULong.MAX_VALUE) {
        println(value)
    }
    for (value in 3u downTo 0u step 3) {
        println(value)
    }
    for (value in 9223372036854775810UL downTo 9223372036854775806UL step 2L) {
        println(value)
    }
    for (value in (ULong.MAX_VALUE - 3UL)..<ULong.MAX_VALUE step 2L) {
        println(value)
    }

    for (value in UInt.MAX_VALUE..0u step 2) {
        println("Unexpected value in empty UInt range: $value")
    }
    for (value in ULong.MAX_VALUE..0UL step 2L) {
        println("Unexpected value in empty ULong range: $value")
    }
    for (value in 0u..<0u step 2) {
        println("Unexpected value in empty open UInt range: $value")
    }
    for (value in ULong.MAX_VALUE..<0UL step 2L) {
        println("Unexpected value in empty open ULong range: $value")
    }
    println("Done")
}
