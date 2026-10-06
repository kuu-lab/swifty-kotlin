// SKIP-DIFF (DEBT-DIFF-011): named local `object` declarations are a
// KSwiftK superset over JVM Kotlin — kotlinc rejects them at compile time
// ("named object 'Local' cannot be local. Try to use an anonymous object
// instead."), so no reference oracle exists. KUU-555 regression coverage is
// pinned by Tests/CompilerCoreTests/GoldenCases/{Parser,Sema}/local_named_nominal
// and LocalNamedNominalTypingTests; kswiftc runs this file printing 5 7 9 3 6.

fun localObjectCase(): Int {
    object Local {
        val v = 5
    }
    return Local.v
}

open class Base(val v: Int)

fun localObjectSuperCase(x: Int): Int {
    object Named : Base(x)
    return Named.v
}

class Outer {
    fun localObjectInMethod(): Int {
        object Local {
            val v = 9
        }
        return Local.v
    }
}

fun lambdaCase(): Int {
    val f = {
        object L {
            val v = 3
        }
        L.v
    }
    return f()
}

fun captureCase(a: Int): Int {
    object L {
        val v = a + 1
    }
    return L.v
}

fun main() {
    println(localObjectCase())
    println(localObjectSuperCase(7))
    println(Outer().localObjectInMethod())
    println(lambdaCase())
    println(captureCase(5))
}
