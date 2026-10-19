var readCount = 0
var writeCount = 0
var stored = 0
var value: Int
    get() { readCount++; return stored }
    set(newValue) { writeCount++; stored = newValue }

fun box(): String {
    value++
    return "r=$readCount,w=$writeCount,v=$stored"
}

class Holder {
    var reads = 0
    var writes = 0
    var stored = 0
    var value: Int
        get() { reads++; return stored }
        set(newValue) { writes++; stored = newValue }
}

fun checkIncDecExpressionsAndControls(): String {
    readCount = 0
    writeCount = 0
    val postIncrement = value++
    if (postIncrement != 1 || readCount != 1 || writeCount != 1 || stored != 2) return "postfix increment"

    readCount = 0
    writeCount = 0
    val preIncrement = ++value
    if (preIncrement != 3 || readCount != 2 || writeCount != 1 || stored != 3) return "prefix increment"

    readCount = 0
    writeCount = 0
    val postDecrement = value--
    if (postDecrement != 3 || readCount != 1 || writeCount != 1 || stored != 2) return "postfix decrement"

    readCount = 0
    writeCount = 0
    val preDecrement = --value
    if (preDecrement != 1 || readCount != 2 || writeCount != 1 || stored != 1) return "prefix decrement"

    readCount = 0
    writeCount = 0
    value = value + 1
    if (readCount != 1 || writeCount != 1 || stored != 2) return "explicit assignment"

    val holder = Holder()
    val memberPostfix = holder.value++
    if (memberPostfix != 0 || holder.reads != 1 || holder.writes != 1 || holder.stored != 1) return "member property"

    return "OK"
}

fun main() {
    println(box())
    println(checkIncDecExpressionsAndControls())
}
