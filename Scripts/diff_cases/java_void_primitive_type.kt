fun box(): String {
    val voidClass = Void::class
    val primitiveClass = voidClass.javaPrimitiveType
    val nothingClass = Nothing::class
    val nothingPrimitiveClass = nothingClass.javaPrimitiveType
    return if (primitiveClass?.kotlin == voidClass && nothingPrimitiveClass?.kotlin == nothingClass) {
        "OK"
    } else {
        "FAIL"
    }
}

fun main() {
    println(box())
}
