fun main() {
    val default = OutOfMemoryError()
    println(default.message)

    val withMessage = OutOfMemoryError("out of memory")
    println(withMessage.message)

    val caught = try {
        throw OutOfMemoryError("thrown")
    } catch (e: Error) {
        "caught: ${e.message}"
    }
    println(caught)
}
