fun main() {
    try {
        "abc"[5]
    } catch (e: StringIndexOutOfBoundsException) {
        println("SIOOBE")
    } catch (e: IndexOutOfBoundsException) {
        println("IOOBE")
    }

    try {
        "abc"[-1]
    } catch (e: ArrayIndexOutOfBoundsException) {
        println("wrong array sibling")
    } catch (e: java.lang.StringIndexOutOfBoundsException) {
        println("qualified SIOOBE")
    }

    try {
        "abc"[3]
    } catch (e: IndexOutOfBoundsException) {
        println("parent")
    }

    try {
        throw ArrayIndexOutOfBoundsException("array")
    } catch (e: StringIndexOutOfBoundsException) {
        println("wrong string sibling")
    } catch (e: IndexOutOfBoundsException) {
        println("array parent")
    }

    println(StringIndexOutOfBoundsException().message)
    println(StringIndexOutOfBoundsException("explicit").message)
    println(StringIndexOutOfBoundsException(null).message)
    println(StringIndexOutOfBoundsException(-5).message)
    println(StringIndexOutOfBoundsException(Int.MIN_VALUE).message)
    println(StringIndexOutOfBoundsException(Int.MAX_VALUE).message)

    try {
        throw StringIndexOutOfBoundsException(5)
    } catch (e: StringIndexOutOfBoundsException) {
        println(e.message)
        println(e is IndexOutOfBoundsException)
    }

    val value: Throwable = StringIndexOutOfBoundsException("typed")
    println(value is StringIndexOutOfBoundsException)
    println(value is IndexOutOfBoundsException)
    println(value is ArrayIndexOutOfBoundsException)
    println((value as java.lang.StringIndexOutOfBoundsException).message)
    try {
        throw StringIndexOutOfBoundsException("thrown")
    } catch (e: IllegalArgumentException) {
        println("wrong unrelated sibling")
    } catch (e: StringIndexOutOfBoundsException) {
        println(e.message)
    }
}
