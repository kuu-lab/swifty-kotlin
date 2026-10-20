package kotlin.reflect.jvm.internal

// Render the logical Kotlin types recorded in metadata, rather than the
// identity string of the runtime wrapper or an erased JVM return descriptor.
internal fun renderRuntimeType(metadata: RuntimeMetadata, type: Proto, parameters: List<Proto>): String {
    var name = ""
    if (type.has(6)) name = metadata.string(type.number(6)).replace("/", ".").replace("$", ".")
    else if (type.has(9)) name = metadata.string(type.number(9))
    else if (type.has(7)) {
        val id = type.number(7)
        for (parameter in parameters) if (parameter.number(1) == id) name = metadata.string(parameter.number(2))
        if (name.isEmpty() && metadata.isClass) {
            for (parameter in metadata.root.children(5)) if (parameter.number(1) == id) name = metadata.string(parameter.number(2))
        }
    }
    if (name.isEmpty()) name = "kotlin.Any"
    val arguments = type.children(2)
    val function = name.startsWith("kotlin.Function") || name.startsWith("kotlin.coroutines.SuspendFunction")
    var result = name
    if (function && !arguments.isEmpty()) {
        var extension = false
        for (annotation in type.children(100)) {
            if (metadata.string(annotation.number(1)) == "kotlin/ExtensionFunctionType") extension = true
        }
        val loweredSuspend = (type.number(1) and 1) != 0
        var last = arguments.size - 1
        var returnType = metadata.type(arguments[last], 2, 3)
        if (loweredSuspend && last > 0) {
            // Official producers encode suspend R as (..., Continuation<R>) -> Any?.
            val continuation = metadata.type(arguments[last - 1], 2, 3)
            val results = continuation.children(2)
            if (!results.isEmpty()) {
                returnType = metadata.type(results[0], 2, 3)
                last--
            }
        }
        result = if (loweredSuspend || name.startsWith("kotlin.coroutines.SuspendFunction")) "suspend " else ""
        var first = 0
        if (extension) {
            result += renderRuntimeType(metadata, metadata.type(arguments[0], 2, 3), parameters) + "."
            first = 1
        }
        result += "("
        var index = first
        while (index < last) {
            if (index != first) result += ", "
            result += renderRuntimeType(metadata, metadata.type(arguments[index], 2, 3), parameters)
            index++
        }
        result += ") -> " + renderRuntimeType(metadata, returnType, parameters)
    } else if (!arguments.isEmpty()) {
        result += "<"
        var index = 0
        while (index < arguments.size) {
            if (index != 0) result += ", "
            val argument = arguments[index]
            val variance = argument.number(1, 2)
            if (variance == 3) result += "*"
            else {
                if (variance == 0) result += "in "
                if (variance == 1) result += "out "
                result += renderRuntimeType(metadata, metadata.type(argument, 2, 3), parameters)
            }
            index++
        }
        result += ">"
    }
    if (type.number(3) != 0) result = if (function) "($result)?" else result + "?"
    if (type.has(5) || type.has(8)) {
        val upper = renderRuntimeType(metadata, metadata.type(type, 5, 8), parameters)
        result = if (upper == result + "?") result + "!" else "($result..$upper)"
    }
    return result
}
