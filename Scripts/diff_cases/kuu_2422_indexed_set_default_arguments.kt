// Based on JetBrains Kotlin v2.3.10 codegen/box/defaultArguments/convention/plusAssignWithDefaults.kt
// https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/defaultArguments/convention/plusAssignWithDefaults.kt
class X {
    var result: String = "fail"

    operator fun get(name: String, type: Int = 100) = name + type

    operator fun set(name: String, defaultParam: String = "_default_", value: String) {
        result = name + defaultParam + value
    }
}

class Y {
    var result: String = "fail"

    operator fun get(name: String, type: String = "_default_", type2: Int = 2) = name + type + type2

    operator fun set(name: String, defaultParam: String = "_default_in_setter_", value: String) {
        result = name + defaultParam + value
    }
}

class AssignmentBox {
    var result: String = "fail"

    operator fun set(name: String, marker: Int = 0, value: String) {
        result = "$name:$marker:$value"
    }
}

class PlainBox {
    var result: String = "fail"

    operator fun get(name: String) = ""

    operator fun set(name: String, value: String) {
        result = "$name:$value"
    }
}

fun box(): String {
    val x = X()
    x["index"] += "OK"
    if (x.result != "index_default_index100OK") return "fail 1: ${x.result}"

    val y = Y()
    y["index"] += "OK"
    if (y.result != "index_default_in_setter_index_default_2OK") return "fail 2: ${y.result}"

    val assignment = AssignmentBox()
    assignment["index"] = "OK"
    if (assignment.result != "index:0:OK") return "fail 3: ${assignment.result}"
    assignment.set("named", value = "OK")
    if (assignment.result != "named:0:OK") return "fail 4: ${assignment.result}"

    val plain = PlainBox()
    plain["index"] += "OK"
    if (plain.result != "index:OK") return "fail 5: ${plain.result}"

    return "OK"
}

fun main() {
    println(box())
}
