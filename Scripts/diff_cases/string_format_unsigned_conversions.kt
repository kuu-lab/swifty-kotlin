// KUU-4146: java.util.Formatter only accepts Byte/Short/Integer/Long for
// %d/%o/%x/%X (and Byte/Short/Integer for %c). Boxed unsigned Kotlin types
// (UByte/UShort/UInt share RuntimeIntBox; ULong has its own box) and enum
// ordinals are not integral arguments and must throw
// IllegalFormatConversionException with JVM's "<conversion> != <class name>"
// message (%t*/%T* reports the date-time suffix character).

fun check(template: String, arg: Any?) {
    try {
        println(template.format(arg))
    } catch (e: Exception) {
        println("${e::class.simpleName}: ${e.message}")
    }
}

enum class Color { RED }

fun main() {
    val ub: UByte = 255u
    val us: UShort = 65535u
    val ui: UInt = 0xffffffffu
    val ul: ULong = 0xffffffffffffffffuL

    // Integral conversions reject every unsigned kind.
    for (template in listOf("%d", "%o", "%x", "%X", "%5d", "%08x", "%#x", "%#o", "%(d", "%,d")) {
        check(template, ub)
        check(template, us)
        check(template, ui)
        check(template, ul)
    }
    // %c/%f/%e/%g/%a/%t* reject them too.
    for (template in listOf("%c", "%f", "%e", "%g", "%a", "%tQ", "%TY")) {
        check(template, ub)
        check(template, us)
        check(template, ui)
        check(template, ul)
    }
    // %s/%b/%h accept them like the JVM does.
    for (template in listOf("%s", "%S", "%b", "%h")) {
        check(template, ub)
        check(template, us)
        check(template, ui)
        check(template, ul)
    }
    check("%s %s", 1u)

    // Argument indexing, < reuse, and companion form all hit the same check.
    check("%1\$x", ui)
    check("%x %<x", ui)
    try {
        println(String.format("%d", ub))
    } catch (e: Exception) {
        println("${e::class.simpleName}: ${e.message}")
    }
    try {
        println("%s %s".format("a"))
    } catch (e: Exception) {
        println("${e::class.simpleName}: ${e.message}")
    }

    // Boxed enum ordinals are rejected too (JVM: d != Color).
    check("%d", Color.RED)
    check("%x", Color.RED)
    check("%c", Color.RED)

    // Other argument kinds already rejected; JVM class names in messages.
    check("%d", "s")
    check("%d", 1.0)
    check("%d", 1.5f)
    check("%d", true)
    check("%d", 'z')
    check("%c", 5L)
    check("%f", 1)
    check("%tQ", 0)
    check("%d", Unit)
    check("%d", 1..3)

    // Signed integral types still format normally. (Negative Byte/Short %x/%o
    // masking is KUU-3985's separate fix; %d keeps the signed value.)
    check("%d", (-29).toByte())
    check("%d", (-30000).toShort())
    check("%x", -29)
    check("%x", -29L)
    check("%o", -29)
    check("%o", 8L)
    check("%c", 65)

    // null stays "null" for every conversion.
    check("%d", null)
    check("%x", null)
    check("%s", null)

    // IllegalFormatCodePointException reports the hex code point like the JVM.
    check("%c", -1)
    check("%c", 0x110000)
    check("%c", (-29).toByte())

    // KUU-4147: the alternate-form prefix survives on zero (C's printf drops
    // it); non-zero behavior is unchanged. Every boxed integer width hits the
    // same zero path (Byte/Short/Int share RuntimeIntBox).
    check("%#x", 0)
    check("%#X", 0)
    check("%#o", 0)
    check("%#x", 0.toByte())
    check("%#o", 0.toByte())
    check("%#x", 0.toShort())
    check("%#o", 0.toShort())
    check("%#x", 0L)
    check("%#o", 0L)
    check("%#X", 0L)
    check("%#5x", 0)
    check("%#05x", 0)
    check("%#-6x|", 0)
    check("%#5o", 0)
    check("%#x", 26)
    check("%#o", 26)
    check("%#x", -1)
}
