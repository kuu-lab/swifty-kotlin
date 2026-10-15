package canonicalnames

class CanonicalNameSample
class CanonicalNameOuter { class Inner }

fun box(): String {
    val names = listOf(
        Boolean::class.javaPrimitiveType!!.canonicalName,
        Char::class.javaPrimitiveType!!.canonicalName,
        Byte::class.javaPrimitiveType!!.canonicalName,
        Short::class.javaPrimitiveType!!.canonicalName,
        Int::class.javaPrimitiveType!!.canonicalName,
        Float::class.javaPrimitiveType!!.canonicalName,
        Long::class.javaPrimitiveType!!.canonicalName,
        Double::class.javaPrimitiveType!!.canonicalName,
        Nothing::class.javaPrimitiveType!!.canonicalName,
        String::class.java.canonicalName,
        Any::class.java.canonicalName,
        CanonicalNameSample::class.java.canonicalName,
        CanonicalNameOuter.Inner::class.java.canonicalName,
        kotlin.RuntimeException::class.java.canonicalName
    )
    val expected = listOf(
        "boolean", "char", "byte", "short", "int", "float", "long", "double", "void",
        "java.lang.String", "java.lang.Object", "canonicalnames.CanonicalNameSample",
        "canonicalnames.CanonicalNameOuter.Inner", "java.lang.RuntimeException"
    )
    return if (names == expected) "OK" else names.joinToString("|")
}

fun main() {
    println(box())
}
