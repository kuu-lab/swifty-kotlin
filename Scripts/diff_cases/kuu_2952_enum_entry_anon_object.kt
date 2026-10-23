// Regression for KUU-2952: an anonymous object inside an enum entry body
// captures the entry receiver, so entry properties resolve both from its
// property initializers and from member functions called later. Adapted
// from JetBrains Kotlin's public box tests enum/kt7257_anonObjectInit.kt
// and enum/kt7257_anonObjectMethod.kt.

enum class X {
    B {
        val value2 = "K"

        val anonObject = object {
            val value3 = "O" + value2

            override fun toString(): String = value3
        }

        override val value = anonObject.toString()
    };

    abstract val value: String
}

enum class Y {
    B {
        val value2 = "K"

        val anonObject = object {
            override fun toString(): String = "O" + value2
        }

        override val value = anonObject.toString()
    };

    abstract val value: String
}

fun box() = "${X.B.value}:${Y.B.value}"

fun main() {
    println(box())
}
