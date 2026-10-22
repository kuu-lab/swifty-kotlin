// DIFF_JVM
// Adapted from Kotlin 2.3.10 compiler/testData/codegen/box/constructorCall/regularConstructorCallEvaluationOrder.kt.
var log = ""

fun <T> logged(msg: String, value: T): T {
    log += msg
    return value
}

class Foo(i: Int, j: Int) {
    init {
        log += "<init>"
    }

    companion object {
        init {
            log += "<clinit>"
        }
    }
}

fun box(): String {
    Foo(logged("i", 1), logged("j", 2))
    val result = log
    return if (result == "<clinit>ij<init>") "OK" else "Fail: '$result'"
}

var events = ""

fun record(label: String): Int {
    events += label
    return 1
}

class Ordered(first: Int, second: Int) {
    companion object {
        init {
            events += "C"
        }
    }

    init {
        events += "I"
    }
}

class Plain(value: Int) {
    init {
        events += "I"
    }
}

class ExplicitOrdered(value: Int) {
    companion object {
        init {
            events += "C"
        }
    }

    init {
        events += "I"
    }
}

fun main() {
    println(box())

    events = ""
    Ordered(record("A"), record("B"))
    val first = events
    Ordered(record("C"), record("D"))
    val repeated = events

    events = ""
    Plain(record("P"))
    val noCompanion = events

    events = ""
    ExplicitOrdered.Companion
    ExplicitOrdered(record("X"))
    val afterExplicit = events

    println("$first|$repeated|$noCompanion|$afterExplicit")
}
