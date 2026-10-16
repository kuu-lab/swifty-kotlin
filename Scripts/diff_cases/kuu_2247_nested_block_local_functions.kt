var result = ""

fun overload() {
    fun local() {
        result += "1"
    }
    local()
}

fun overload(unused: String) {
    fun local() {
        result += "2"
    }
    local()
    if ("".length < 1) {
        fun local() {
            result += "3"
        }
        local()
    }
}

class C {
    fun overload() {
        fun local() {
            result += "4"
        }
        local()
    }
    fun overload(unused: String) {
        fun local() {
            result += "5"
        }
        local()
        if ("".length < 1) {
            fun local() {
                result += "6"
            }
            local()
        }
    }
}

fun box(): String {
    overload()
    overload("")
    C().overload()
    C().overload("")
    return if (result == "123456") "OK" else "Fail: $result"
}

fun minimalReproduction(): String {
    if (true) {
        fun inner() = "OK"
        inner()
    }
    return "OK"
}

fun directDeclarationControl(): String {
    fun inner() = "OK"
    inner()
    return "OK"
}

fun whileLoopLocalFunction(): String {
    var value = ""
    while (value.isEmpty()) {
        fun local() = "while"
        value = local()
    }
    return value
}

fun forLoopLocalFunction(): String {
    var value = ""
    for (index in 1..1) {
        fun local() = "for"
        value = local()
    }
    return value
}

fun lambdaNestedBlockLocalFunction(): String {
    val callback: () -> String = {
        if (true) {
            fun local() = "lambda"
            local()
        } else {
            "FAIL"
        }
    }
    return callback()
}

fun lexicalFunctionShadowing(): String {
    fun local() = "outer"
    val nested = if (true) {
        fun local() = "inner"
        local()
    } else {
        "FAIL"
    }
    return nested + local()
}

fun main() {
    println(box())
    println(minimalReproduction())
    println(directDeclarationControl())
    println(whileLoopLocalFunction())
    println(forLoopLocalFunction())
    println(lambdaNestedBlockLocalFunction())
    println(lexicalFunctionShadowing())
}
