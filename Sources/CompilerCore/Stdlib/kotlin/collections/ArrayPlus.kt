package kotlin.collections

// KUU-756: Array concatenation is source-backed, using the existing copyOf
// implementation to keep the result's element type and original contents.
@Suppress("UNCHECKED_CAST")
public operator fun <T> Array<T>.plus(element: T): Array<T> {
    val result = this.copyOf(this.size + 1) as Array<T>
    result[this.size] = element
    return result
}

@Suppress("UNCHECKED_CAST")
public operator fun <T> Array<T>.plus(elements: Array<out T>): Array<T> {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size) as Array<T>
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

@Suppress("UNCHECKED_CAST")
public operator fun <T> Array<T>.plus(elements: Collection<T>): Array<T> {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size) as Array<T>
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}

public fun <T> Array<T>.plusElement(element: T): Array<T> = this.plus(element)

public operator fun IntArray.plus(element: Int): IntArray {
    val result = this.copyOf(this.size + 1)
    result[this.size] = element
    return result
}

public operator fun IntArray.plus(elements: IntArray): IntArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

public operator fun IntArray.plus(elements: Collection<Int>): IntArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}

public operator fun ByteArray.plus(element: Byte): ByteArray {
    val result = this.copyOf(this.size + 1)
    result[this.size] = element
    return result
}

public operator fun ByteArray.plus(elements: ByteArray): ByteArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

public operator fun ByteArray.plus(elements: Collection<Byte>): ByteArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}

public operator fun LongArray.plus(element: Long): LongArray {
    val result = this.copyOf(this.size + 1)
    result[this.size] = element
    return result
}

public operator fun LongArray.plus(elements: LongArray): LongArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

public operator fun LongArray.plus(elements: Collection<Long>): LongArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}

public operator fun ShortArray.plus(element: Short): ShortArray {
    val result = this.copyOf(this.size + 1)
    result[this.size] = element
    return result
}

public operator fun ShortArray.plus(elements: ShortArray): ShortArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

public operator fun ShortArray.plus(elements: Collection<Short>): ShortArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}

public operator fun DoubleArray.plus(element: Double): DoubleArray {
    val result = this.copyOf(this.size + 1)
    result[this.size] = element
    return result
}

public operator fun DoubleArray.plus(elements: DoubleArray): DoubleArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

public operator fun DoubleArray.plus(elements: Collection<Double>): DoubleArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}

public operator fun FloatArray.plus(element: Float): FloatArray {
    val result = this.copyOf(this.size + 1)
    result[this.size] = element
    return result
}

public operator fun FloatArray.plus(elements: FloatArray): FloatArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

public operator fun FloatArray.plus(elements: Collection<Float>): FloatArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}

public operator fun CharArray.plus(element: Char): CharArray {
    val result = this.copyOf(this.size + 1)
    result[this.size] = element
    return result
}

public operator fun CharArray.plus(elements: CharArray): CharArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

public operator fun CharArray.plus(elements: Collection<Char>): CharArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}

public operator fun BooleanArray.plus(element: Boolean): BooleanArray {
    val result = this.copyOf(this.size + 1)
    result[this.size] = element
    return result
}

public operator fun BooleanArray.plus(elements: BooleanArray): BooleanArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = 0
    while (i < elements.size) {
        result[originalSize + i] = elements[i]
        i++
    }
    return result
}

public operator fun BooleanArray.plus(elements: Collection<Boolean>): BooleanArray {
    val originalSize = this.size
    val result = this.copyOf(originalSize + elements.size)
    var i = originalSize
    for (element in elements) {
        result[i] = element
        i++
    }
    return result
}
