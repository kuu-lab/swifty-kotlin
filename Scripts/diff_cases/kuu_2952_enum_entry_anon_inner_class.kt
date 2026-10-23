// Regression for KUU-2952: Kotlin/JVM permits `inner class` inside an
// anonymous object expression, and members there reach the enclosing enum
// entry's properties through the anonymous object's $outer link.
// Adapted from JetBrains Kotlin's public box test
// enum/deepInnerClassInEnumEntryClass2.kt.

enum class A {
    X {
        val k = "K"

        val anonObject = object {
            inner class Inner {
                val x = "O" + k
            }

            val innerX = Inner().x

            override fun toString() = innerX
        }

        override val test = anonObject.toString()
    };

    abstract val test: String
}

fun box() = A.X.test

fun main() {
    println(box())
}
