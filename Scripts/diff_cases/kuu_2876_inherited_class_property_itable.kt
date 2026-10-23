open class MutableBase {
    var size: Int = 56
}

interface MutableSize<T> {
    var size: T
}

class MutableSizeImpl : MutableSize<Int>, MutableBase()

interface ReadSize<T> {
    val size: T
}

open class ReadBase {
    val size: Int = 41
}

class ReadSizeImpl : ReadSize<Int>, ReadBase()

fun readSize(value: MutableSize<Int>): Int = value.size

fun writeSize(value: MutableSize<Int>, size: Int) {
    value.size = size
}

fun readInheritedVal(value: ReadSize<Int>): Int = value.size

fun main() {
    val concrete = MutableSizeImpl()
    println(concrete.size)

    val mutable: MutableSize<Int> = concrete
    println(readSize(mutable))
    writeSize(mutable, 57)
    println(readSize(mutable))

    val readable: ReadSize<Int> = ReadSizeImpl()
    println(readInheritedVal(readable))
}
