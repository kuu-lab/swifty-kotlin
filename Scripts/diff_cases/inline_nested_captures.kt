object InlineByteArrayVisitor {
    inline fun visit(data: ByteArray, action: (ByteArray) -> Unit) {
        action(data)
    }
}

inline fun <T> withOffset(action: (Int) -> T): T = action(3)
inline fun <T> withValue(value: Int, action: (Int) -> T): T = action(value)

fun find(): Int {
    InlineByteArrayVisitor.visit(byteArrayOf(7)) { bytes ->
        withOffset { offset ->
            return bytes[0].toInt() + offset
        }
    }
    return -1
}

fun findConditional(data: ByteArray): Int {
    InlineByteArrayVisitor.visit(data) { bytes ->
        withOffset { offset ->
            if (bytes[0].toInt() > 0) return bytes[0].toInt() + offset
        }
    }
    return -1
}

fun normalReturn(data: ByteArray): Int {
    var result = -1
    InlineByteArrayVisitor.visit(data) { bytes ->
        result = withOffset { offset ->
            return@withOffset bytes[0].toInt() + offset
        }
    }
    return result
}

fun mutableReturn(data: ByteArray): Int {
    var result = 1
    InlineByteArrayVisitor.visit(data) { bytes ->
        withOffset { offset ->
            result += bytes[0].toInt() + offset
            return result
        }
    }
    return -1
}

fun mutableNormalReturn(data: ByteArray): Int {
    var result = 1
    InlineByteArrayVisitor.visit(data) { bytes ->
        withOffset { offset ->
            result += bytes[0].toInt() + offset
        }
        result += bytes[0].toInt()
    }
    return result
}

fun tripleCapture(data: ByteArray): Int {
    InlineByteArrayVisitor.visit(data) { bytes ->
        withOffset { offset ->
            withValue(5) { extra ->
                return bytes[0].toInt() + offset + extra
            }
        }
    }
    return -1
}

fun main() {
    println(find())
    println(findConditional(byteArrayOf(7)))
    println(findConditional(byteArrayOf(11)))
    println(findConditional(byteArrayOf(0)))
    println(normalReturn(byteArrayOf(7)))
    println(normalReturn(byteArrayOf(11)))
    println(mutableReturn(byteArrayOf(7)))
    println(mutableNormalReturn(byteArrayOf(7)))
    println(tripleCapture(byteArrayOf(7)))
}
