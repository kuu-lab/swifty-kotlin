inline fun run2(block: () -> Unit) = block()

class A {
    val prop: Int
    constructor(arg: Boolean) {
        if (arg) {
            prop = 1
            run2 { return }
            throw RuntimeException("fail 0")
        }
        prop = 2
    }
}

fun box(): String {
    val a1 = A(true)
    if (a1.prop != 1) return "fail1: ${a1.prop}"
    val a2 = A(false)
    if (a2.prop != 2) return "fail2: ${a2.prop}"
    return "OK"
}

// KUU-2441 oracle: JetBrains/Kotlin 679366a83f99851b42f64795f10ed803ff011c73,
// compiler/testData/codegen/box/secondaryConstructors/withNonLocalReturn.kt
// Git blob 4ab9a4450b1d05ef24dfed0cfceb25d458b0623d, SHA-256 66560e74a304730006e6a9e3e81d690af603e036cb3ca072728d726d103f2369.
inline fun invokeMini(block: () -> Unit) = block()

class MiniCtor {
    constructor() {
        invokeMini { return }
        throw IllegalStateException("unreachable")
    }
}

fun boxMini(): String {
    MiniCtor()
    return "OK"
}

fun functionControl(): Int {
    invokeMini { return 42 }
    return -1
}

class ConstructorControl {
    var marker = false

    constructor() {
        invokeMini { return@invokeMini }
        marker = true
    }
}

fun main() {
    val first = A(true)
    println(if (first.prop == 1) "A(true)=1" else "A(true)!=1")
    val second = A(false)
    println(if (second.prop == 2) "A(false)=2" else "A(false)!=2")
    MiniCtor()
    println("MiniCtor=OK")
    println(if (functionControl() == 42) "function=42" else "function!=42")
    println(if (ConstructorControl().marker) "labeledReturn=true" else "labeledReturn=false")
}
