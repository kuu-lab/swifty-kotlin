// Regression for KUU-2414. Adapted from JetBrains Kotlin's public box test:
// https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/enum/enumCompanionInit.kt
// The main wrapper exposes box() to the differential harness.

var result = ""

enum class E(a: String) {
    X("x"),
    Y("y");

    init {
        result += "E.init($a);"
    }

    companion object {
        init {
            result += "E.companion.init;"
            val value = E.values()[0].name
            result += "$value;"
        }
    }
}

enum class F(a: String) {
    X("x"),
    Y("y");

    init {
        result += "F.init($a);"
    }

    companion object {
        init {
            result += "F.companion.init;"
        }

        fun foo() {
            result += "F.foo();$X;"
        }
    }
}

enum class G(a: String) {
    X("x"),
    Y("y");

    init {
        result += "G.init($a);"
    }

    object O {
        init {
            result += "G.O.init;"
        }

        fun foo() {
            result += "G.O.foo();$X;"
        }
    }
}

fun box(): String {
    val y = E.Y
    result += "${y.name};"

    F.foo()
    G.O.foo()

    if (result != "E.init(x);E.init(y);E.companion.init;X;Y;F.init(x);F.init(y);F.companion.init;F.foo();X;G.O.init;G.O.foo();X;") {
        return "fail: $result"
    }
    return "OK"
}

fun main() {
    println(box())
}
