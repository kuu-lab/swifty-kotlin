// KUU-2840: exceptions from inlined finally blocks must escape the try scopes
// whose cleanup has already run, while remaining catchable by an outer try.
var result = ""

fun breakCase() {
    for (z in 1..2) {
        try {
            try {
                result += "break"
                break
            } catch (fail: Throwable) {
                result += " catch"
            }
        } finally {
            result += " finally"
            throw RuntimeException()
        }
    }
}

fun continueCase() {
    for (z in 1..2) {
        try {
            try {
                result += "continue"
                continue
            } catch (fail: Throwable) {
                result += " catch"
            }
        } finally {
            result += " finally"
            throw RuntimeException()
        }
    }
}

fun returnCase() {
    try {
        try {
            result += "return"
            return
        } catch (fail: Throwable) {
            result += " catch"
        }
    } finally {
        result += " finally"
        throw RuntimeException()
    }
}

fun outerCatchCase() {
    try {
        for (z in 1..2) {
            try {
                try {
                    result += "outer"
                    break
                } catch (fail: Throwable) {
                    result += " catch"
                }
            } finally {
                result += " finally"
                throw RuntimeException()
            }
        }
    } catch (fail: RuntimeException) {
        result += " outer-catch"
    }
}

fun main() {
    try { breakCase() } catch (fail: RuntimeException) {}
    println(result)
    result = ""
    try { continueCase() } catch (fail: RuntimeException) {}
    println(result)
    result = ""
    try { returnCase() } catch (fail: RuntimeException) {}
    println(result)
    result = ""
    outerCatchCase()
    println(result)
}
