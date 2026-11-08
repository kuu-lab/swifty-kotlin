import java.lang.reflect.Modifier

open class Base { fun baseMethod(x: Int): String = "b$x" }
class Derived : Base() {
    fun ownMethod(s: String): Int = s.length
    companion object { const val K = 1 }
}

fun main() {
    val d = Derived::class.java
    val bm = d.getMethod("baseMethod", Int::class.java)
    println(bm.getName())
    println(bm.getParameterTypes()[0].name)
    val om = d.getMethod("ownMethod", String::class.java)
    println(om.returnType.name)
    try { d.getMethod("missing") } catch (e: NoSuchMethodException) { println("no-method") }

    println(Modifier.isPublic(Modifier.PUBLIC))
    println(Modifier.isFinal(Modifier.PUBLIC or Modifier.FINAL))
    println(Modifier.isInterface(Modifier.INTERFACE or Modifier.ABSTRACT))
    println(Modifier.toString(Modifier.PUBLIC or Modifier.FINAL or Modifier.STATIC))

    println(d.getModifiers())
    println(Modifier.isPublic(d.getModifiers()))
    println(Modifier.isFinal(d.getModifiers()))
    println(String::class.java.getModifiers())
    println(Int::class.java.getModifiers())
}
