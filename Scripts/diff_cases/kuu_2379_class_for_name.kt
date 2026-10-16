// KUU-2379: Class.forName resolves JVM names to the same native class tokens.
package test

class ClassForNameTarget
class ClassForNameOuter {
    class Inner
}

fun main() {
    val stringClass = java.lang.Class.forName("java.lang.String")
    val targetClass = java.lang.Class.forName("test.ClassForNameTarget")
    val nestedClass = java.lang.Class.forName("test.ClassForNameOuter\$Inner")
    println(stringClass == String::class.java)
    println(targetClass == ClassForNameTarget::class.java)
    println(nestedClass == ClassForNameOuter.Inner::class.java)
    println(stringClass.kotlin == String::class)
    println(targetClass.kotlin == ClassForNameTarget::class)
}
