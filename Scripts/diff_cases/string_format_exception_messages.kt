// KUU-4150: the remaining java.util format-exception messages must match the
// JVM byte-for-byte — DuplicateFormatFlagsException reports the single
// repeated flag ('Flags = '-''), IllegalFormatFlagsException reports all
// parsed flags in canonical order, FormatFlagsConversionMismatchException
// reports 'Conversion = <c>, Flags = <flags>' unquoted,
// MissingFormatWidthException reports the reconstructed specifier
// (FormatSpecifier.toString(), canonical flags before the argument index),
// IllegalFormatWidthException reports the bare width (Int.MIN_VALUE on
// parseInt overflow), and UnknownFormatConversionException reports
// 'Conversion = '<c>'' — the first character after '%' when the specifier
// itself is incomplete.

fun check(template: String, arg: Any?) {
    try {
        println(template.format(arg))
    } catch (e: Exception) {
        println("${e::class.simpleName}: ${e.message}")
    }
}

fun checkNoArg(template: String) {
    try {
        println(template.format())
    } catch (e: Exception) {
        println("${e::class.simpleName}: ${e.message}")
    }
}

fun main() {
    // DuplicateFormatFlagsException — the first repeated flag only.
    for (template in listOf("%--5s", "%00d", "%++d", "%##x", "%<<s", "%- -c", "%--+d")) {
        check(template, 5)
    }

    // IllegalFormatFlagsException — all parsed flags, canonical order.
    for (template in listOf("%+ d", "%-0d", "%0%", "%+%", "%,n", "%- %", "%-+0 5d", "%-n")) {
        check(template, 5)
    }

    // FormatFlagsConversionMismatchException — unquoted
    // "Conversion = <c>, Flags = <flags>"; %s '#'/o/x sign flags are
    // per-argument checks.
    for (template in listOf(
        "%#s", "%0s", "%+s", "%,s", "%(s", "% s", "%#S", "%#h", "%+b", "%#b",
        "%0c", "%+c", "%#d", "%,o", "%+x", "%(x", "% x", "% (x",
        "%,e", "%(a", "%,a", "%#g", "%#tQ", "%+tQ", "%0tQ",
    )) {
        check(template, 5)
    }
    check("%#s", "text")
    check("%+x", 1L)
    check("% x", -1L)
    check("%(x", -1L)
    check("%+o", 8L)
    check("% o", 8L)
    check("%(o", -8L)

    // MissingFormatWidthException — the reconstructed specifier: canonical
    // flags, then the argument index, then width/precision.
    for (template in listOf("%-d", "%-0f", "%-(d", "%-+d", "%0+d", "%0#d", "%-+,s", "%-%", "%-.2d")) {
        check(template, 5)
    }
    check("%1\$-s", "x")
    check("%1\$-%", "x")
    check("%1\$-d", "x")

    // IllegalFormatWidthException — the bare width; Int.MIN_VALUE when the
    // digits overflow a Java int.
    for (template in listOf("%5n", "%,5n", "%2147483648d", "%99999999999d")) {
        check(template, 5)
    }

    // UnknownFormatConversionException — 'Conversion = '<c>'': an
    // unsupported letter reports itself; an unterminated specifier reports
    // the first character after '%'.
    for (template in listOf(
        "%q", "%y", "%D", "%i", "%u", "%", "%.", "%.d", "%-", "%+0",
        "%t", "%T", "%tq", "%Tq", "%t%", "%T%", "%1\$q", "%-q", "%.2q", "%5q", "% z",
    )) {
        check(template, 5)
    }
    check("%s %q", "x")

    // MissingFormatArgumentException — same reconstructed-specifier shape.
    checkNoArg("%<s")
    checkNoArg("%3\$d")
    checkNoArg("%#s")
    checkNoArg("%+x")

    // Precision and argument-index messages are JVM-shaped too.
    for (template in listOf("%.2d", "%5.2n", "%.2n", "%.2tq", "%2147483648.1f", "%.2147483648f")) {
        check(template, 5)
    }
    for (template in listOf("%0\$d", "%99999999999\$d")) {
        check(template, 5)
    }

    // The specifier checks stay ahead of the argument checks: a bad
    // combination reports before missing arguments or conversion types.
    check("%#0s", "text")
    check("%-05s", "text")
    check("%(x", "text")
    check("%+x", "text")
}
