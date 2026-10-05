import java.lang.StringIndexOutOfBoundsException as StringBounds

fun main() {
    try {
        "abc"[5]
    } catch (e: StringBounds) {
        println("alias SIOOBE")
    }
    try {
        throw StringBounds("alias")
    } catch (e: java.lang.StringIndexOutOfBoundsException) {
        println(e.message)
    }
}
