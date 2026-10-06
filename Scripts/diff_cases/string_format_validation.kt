import java.util.Locale
import java.util.IllegalFormatException
import java.util.IllegalFormatConversionException
import java.util.MissingFormatArgumentException

fun checkFormat(template: String, vararg args: Any?) {
    try {
        println(template.format(*args))
    } catch (e: IllegalFormatException) {
        println("invalid")
    }
    try {
        println(String.format(Locale("en", "US"), template, *args))
    } catch (e: IllegalFormatException) {
        println("invalid")
    }
}

fun main() {
    checkFormat("%.2x", 255)
    checkFormat("%d", "s")
    checkFormat("%s %s", "a")
    checkFormat("%+s", "x")
    checkFormat("%05s", "x")
    checkFormat("%c", "ab")
    checkFormat("%.2d", 5)
    checkFormat("%8.3d", 5)
    checkFormat("%q", 5)
    checkFormat("%<s", "x")
    checkFormat("%--5s", "x")
    checkFormat("%-s", "x")
    checkFormat("%+ d", 1)
    checkFormat("%f", 1)
    checkFormat("%d", 1.0)
    checkFormat("%tQ", "x")
    checkFormat("%c", -1)
    checkFormat("%c", 0x110000)
    checkFormat("%i", 1)
    checkFormat("%.s", "x")
    checkFormat("%")
    checkFormat("%5n")
    checkFormat("%+%")
    checkFormat("%s %q")
    checkFormat("%0s", "x")
    checkFormat("%0c", 'A')
    checkFormat("%0tQ", 0L)
    checkFormat("%0%")
    checkFormat("%-.2d", 1)
    checkFormat("%#s")
    checkFormat("%#s", "x")
    checkFormat("%100000sX%d", "x", "s")
    checkFormat("%100000sX%s", "x")
    checkFormat("%.2f", null)
    checkFormat("%1$.2f|%1$.2h|%1$.2b|%2$.2B", null, true)
    checkFormat("%(d", Long.MIN_VALUE)
    checkFormat("%d", null)
    checkFormat("%b", null)
    checkFormat("%s", null)
    checkFormat("%2\$s %s %<s", "a", "b")
    checkFormat("%05d %.2f %c", 42, 1.25, 'A')
    checkFormat("%5%/%n")
    try {
        String.format("%d", "s")
    } catch (e: IllegalFormatConversionException) {
        println("conversion")
    }
    try {
        "%s %s".format("a")
    } catch (e: MissingFormatArgumentException) {
        println("missing")
    }
    try {
        println("%b".format(null))
    } catch (e: MissingFormatArgumentException) {
        println("null-locale-missing")
    }
    println("%b".format(null as Any?))
}
