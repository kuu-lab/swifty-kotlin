annotation class Anno(val value: String)

open class Parent {
    fun inherited() {}
}

class DeclaredMethods : Parent() {
    @Anno("OK")
    val property: Int
        get() = 42

    fun marker() {}
}

fun declaredMethods(type: java.lang.Class<*>): Array<java.lang.reflect.Method> = type.getDeclaredMethods()

fun main() {
    val methods = declaredMethods(DeclaredMethods::class.java)
    var hasMarker = false
    var hasInherited = false
    var hasSyntheticAnnotations = false
    for (method in methods) {
        val name = method.getName()
        if (name == "marker") hasMarker = true
        if (name == "inherited") hasInherited = true
        if (name == "getProperty\$annotations" && method.isSynthetic()) hasSyntheticAnnotations = true
    }
    println(hasMarker)
    println(!hasInherited)
    println(hasSyntheticAnnotations)
}
