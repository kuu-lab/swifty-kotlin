class MyObject

fun box(): String {
    val prefix = MyObject::class.qualifiedName!!.removeSuffix("MyObject")

    try {
        MyObject() as String
    } catch (e: Throwable) {
        if (e !is ClassCastException) return "wrong exception: $e"
        if (e.message != "class ${prefix}MyObject cannot be cast to class kotlin.String") {
            return "global class: ${e.message}"
        }
    }

    try {
        (42 as Any) as String
    } catch (e: Throwable) {
        if (e !is ClassCastException) return "wrong exception: $e"
        if (e.message != "class kotlin.Int cannot be cast to class kotlin.String") {
            return "primitive: ${e.message}"
        }
    }

    val sourceArray: Any = arrayOf("value")
    try {
        sourceArray as Array<Int>
    } catch (e: Throwable) {
        if (e !is ClassCastException) return "wrong exception: $e"
        if (e.message != "class kotlin.Array cannot be cast to class kotlin.Array") {
            return "array: ${e.message}"
        }
    }

    class MyLocalObject
    try {
        MyObject() as MyLocalObject
    } catch (e: Throwable) {
        if (e !is ClassCastException) return "wrong exception: $e"
        if (e.message != "class ${prefix}MyObject cannot be cast to class ${prefix}box\$MyLocalObject") {
            return "local target: ${e.message}"
        }
    }

    try {
        MyLocalObject() as MyObject
    } catch (e: Throwable) {
        if (e !is ClassCastException) return "wrong exception: $e"
        if (e.message != "class ${prefix}box\$MyLocalObject cannot be cast to class ${prefix}MyObject") {
            return "local source: ${e.message}"
        }
    }

    try {
        object {} as MyObject
    } catch (e: Throwable) {
        if (e !is ClassCastException) return "wrong exception: $e"
        if (e.message != "class ${prefix}box$1 cannot be cast to class ${prefix}MyObject") {
            return "anonymous: ${e.message}"
        }
    }

    return "OK"
}

fun main() {
    println(box())
}
