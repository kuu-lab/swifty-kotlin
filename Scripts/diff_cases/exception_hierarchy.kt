fun main() {
    val cause = Exception("cause")

    println(Error().message)
    println(Error("error").message)
    println(Error("error", cause).cause?.message)
    println(Error(cause).cause?.message)

    println(IllegalArgumentException().message)
    println(IllegalArgumentException("argument").message)
    println(IllegalArgumentException("argument", cause).cause?.message)
    println(IllegalArgumentException(cause).cause?.message)

    println(IndexOutOfBoundsException().message)
    println(IndexOutOfBoundsException("index").message)
    println(AssertionError(42).message)
    println(AssertionError("assertion", cause).cause?.message)

    val caught = try {
        throw IllegalStateException("state")
    } catch (e: IllegalArgumentException) {
        "wrong sibling"
    } catch (e: RuntimeException) {
        "runtime parent"
    }
    println(caught)

    val value: Throwable = IllegalArgumentException("cast")
    println(value is IllegalArgumentException)
    println((value as IllegalArgumentException).message)
}
