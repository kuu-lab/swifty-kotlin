// KSP-620 regression: stdlib-only closure wrappers must not collide with a
// consumer module's synthetic closure symbols.

fun applyTransform(value: String, transform: (String) -> String): String = transform(value)

fun main() {
    val suffix = "!"
    println(applyTransform("01") { it + suffix })
    println(applyTransform("02") { it + suffix })
    println(applyTransform("03") { it + suffix })
    println(applyTransform("04") { it + suffix })
    println(applyTransform("05") { it + suffix })
    println(applyTransform("06") { it + suffix })
    println(applyTransform("07") { it + suffix })
    println(applyTransform("08") { it + suffix })
    println(applyTransform("09") { it + suffix })
    println(applyTransform("10") { it + suffix })
    println(applyTransform("11") { it + suffix })
    println(applyTransform("12") { it + suffix })
    println(applyTransform("13") { it + suffix })
    println(applyTransform("14") { it + suffix })
    println(applyTransform("15") { it + suffix })
    println(applyTransform("16") { it + suffix })
    println(applyTransform("17") { it + suffix })
    println(applyTransform("18") { it + suffix })
    println(applyTransform("19") { it + suffix })
    println(applyTransform("20") { it + suffix })
    println(applyTransform("21") { it + suffix })
}
