fun takesInt(i: Int) = i.javaClass.simpleName
fun <T : Any> generic(t: T) = t.javaClass.simpleName

fun main() {
    println(1.javaClass.simpleName)
    println(1L.javaClass.simpleName)
    println(1.5.javaClass.simpleName)
    println(1.5f.javaClass.simpleName)
    println(true.javaClass.simpleName)
    println('x'.javaClass.simpleName)
    println(2.toByte().javaClass.simpleName)
    println(Short.MAX_VALUE.javaClass.simpleName)
    println("s".javaClass.simpleName)
    println(Any().javaClass.simpleName)

    val i = 42
    println(i.javaClass.simpleName)
    println(takesInt(7))

    val boxed: Any = 1
    println(boxed.javaClass.simpleName)
    println(generic(9))
    println(generic<Int>(10))

    println(Int::class.java.simpleName)
    println(Int::class.java == 1.javaClass)
    println(Int::class.java == Int::class.javaPrimitiveType)
    println(Int::class.java != Int::class.javaObjectType)
    println(Int::class.javaObjectType.simpleName)
    println(1.javaClass.isPrimitive)
    println(Int::class.java.isPrimitive)
    println(Int::class.java.superclass)
    println(Int::class.java == Long::class.javaPrimitiveType)
    println(Byte::class.java == Byte::class.javaPrimitiveType)
    println(Double::class.java == Double::class.javaObjectType)
}
