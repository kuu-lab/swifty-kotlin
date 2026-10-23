package kotlin.collections

public infix fun <T> Array<out T>?.contentEquals(other: Array<out T>?): Boolean = null!!
public fun <T> Array<out T>?.contentHashCode(): Int = null!!
public fun <T> Array<out T>?.contentToString(): String = null!!
public infix fun <T> Array<out T>?.contentDeepEquals(other: Array<out T>?): Boolean = null!!
public fun <T> Array<out T>?.contentDeepHashCode(): Int = null!!
public fun <T> Array<out T>?.contentDeepToString(): String = null!!

public infix fun ByteArray?.contentEquals(other: ByteArray?): Boolean = null!!
public fun ByteArray?.contentHashCode(): Int = null!!
public fun ByteArray?.contentToString(): String = null!!
public fun ByteArray.reversedArray(): ByteArray = null!!
public fun ByteArray.sort(): Unit = null!!
public fun ByteArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun ByteArray.sortDescending(): Unit = null!!
public fun ByteArray.sortedArray(): ByteArray = null!!
public fun ByteArray.sortedArrayDescending(): ByteArray = null!!
public fun ByteArray.binarySearch(element: Byte, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun ShortArray?.contentEquals(other: ShortArray?): Boolean = null!!
public fun ShortArray?.contentHashCode(): Int = null!!
public fun ShortArray?.contentToString(): String = null!!
public fun ShortArray.reversedArray(): ShortArray = null!!
public fun ShortArray.sort(): Unit = null!!
public fun ShortArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun ShortArray.sortDescending(): Unit = null!!
public fun ShortArray.sortedArray(): ShortArray = null!!
public fun ShortArray.sortedArrayDescending(): ShortArray = null!!
public fun ShortArray.binarySearch(element: Short, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun IntArray?.contentEquals(other: IntArray?): Boolean = null!!
public fun IntArray?.contentHashCode(): Int = null!!
public fun IntArray?.contentToString(): String = null!!
public fun IntArray.reversedArray(): IntArray = null!!
public fun IntArray.sort(): Unit = null!!
public fun IntArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun IntArray.sortDescending(): Unit = null!!
public fun IntArray.sortedArray(): IntArray = null!!
public fun IntArray.sortedArrayDescending(): IntArray = null!!
public fun IntArray.binarySearch(element: Int, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun LongArray?.contentEquals(other: LongArray?): Boolean = null!!
public fun LongArray?.contentHashCode(): Int = null!!
public fun LongArray?.contentToString(): String = null!!
public fun LongArray.reversedArray(): LongArray = null!!
public fun LongArray.sort(): Unit = null!!
public fun LongArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun LongArray.sortDescending(): Unit = null!!
public fun LongArray.sortedArray(): LongArray = null!!
public fun LongArray.sortedArrayDescending(): LongArray = null!!
public fun LongArray.binarySearch(element: Long, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun FloatArray?.contentEquals(other: FloatArray?): Boolean = null!!
public fun FloatArray?.contentHashCode(): Int = null!!
public fun FloatArray?.contentToString(): String = null!!
public fun FloatArray.reversedArray(): FloatArray = null!!
public fun FloatArray.sort(): Unit = null!!
public fun FloatArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun FloatArray.sortDescending(): Unit = null!!
public fun FloatArray.sortedArray(): FloatArray = null!!
public fun FloatArray.sortedArrayDescending(): FloatArray = null!!
public fun FloatArray.binarySearch(element: Float, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun DoubleArray?.contentEquals(other: DoubleArray?): Boolean = null!!
public fun DoubleArray?.contentHashCode(): Int = null!!
public fun DoubleArray?.contentToString(): String = null!!
public fun DoubleArray.reversedArray(): DoubleArray = null!!
public fun DoubleArray.sort(): Unit = null!!
public fun DoubleArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun DoubleArray.sortDescending(): Unit = null!!
public fun DoubleArray.sortedArray(): DoubleArray = null!!
public fun DoubleArray.sortedArrayDescending(): DoubleArray = null!!
public fun DoubleArray.binarySearch(element: Double, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun BooleanArray?.contentEquals(other: BooleanArray?): Boolean = null!!
public fun BooleanArray?.contentHashCode(): Int = null!!
public fun BooleanArray?.contentToString(): String = null!!
public fun BooleanArray.reversedArray(): BooleanArray = null!!

public infix fun CharArray?.contentEquals(other: CharArray?): Boolean = null!!
public fun CharArray?.contentHashCode(): Int = null!!
public fun CharArray?.contentToString(): String = null!!
public fun CharArray.reversedArray(): CharArray = null!!
public fun CharArray.sort(): Unit = null!!
public fun CharArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun CharArray.sortDescending(): Unit = null!!
public fun CharArray.sortedArray(): CharArray = null!!
public fun CharArray.sortedArrayDescending(): CharArray = null!!
public fun CharArray.binarySearch(element: Char, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public fun <T> Array<T>.reversedArray(): Array<T> = null!!
public fun <T> Array<out T>.sort(): Unit = null!!
public fun <T> Array<out T>.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun <T : Comparable<T>> Array<out T>.sortDescending(): Unit = null!!
public fun <T> Array<T>.sortWith(comparator: Comparator<in T>): Unit = null!!
public fun <T : Comparable<T>> Array<T>.sortedArray(): Array<T> = null!!
public fun <T : Comparable<T>> Array<T>.sortedArrayDescending(): Array<T> = null!!
public fun <T> Array<T>.sortedArrayWith(comparator: Comparator<in T>): Array<T> = null!!
public fun <T> Array<out T>.binarySearch(element: T, fromIndex: Int = 0, toIndex: Int = size): Int = null!!
public fun <T> Array<out T>.binarySearch(
    element: T,
    comparator: Comparator<in T>,
    fromIndex: Int = 0,
    toIndex: Int = size
): Int = null!!

public infix fun UByteArray?.contentEquals(other: UByteArray?): Boolean = null!!
public fun UByteArray?.contentHashCode(): Int = null!!
public fun UByteArray?.contentToString(): String = null!!
public fun UByteArray.reversedArray(): UByteArray = null!!
public fun UByteArray.sort(): Unit = null!!
public fun UByteArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun UByteArray.sortDescending(): Unit = null!!
public fun UByteArray.sortedArray(): UByteArray = null!!
public fun UByteArray.sortedArrayDescending(): UByteArray = null!!
public fun UByteArray.binarySearch(element: UByte, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun UShortArray?.contentEquals(other: UShortArray?): Boolean = null!!
public fun UShortArray?.contentHashCode(): Int = null!!
public fun UShortArray?.contentToString(): String = null!!
public fun UShortArray.reversedArray(): UShortArray = null!!
public fun UShortArray.sort(): Unit = null!!
public fun UShortArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun UShortArray.sortDescending(): Unit = null!!
public fun UShortArray.sortedArray(): UShortArray = null!!
public fun UShortArray.sortedArrayDescending(): UShortArray = null!!
public fun UShortArray.binarySearch(element: UShort, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun UIntArray?.contentEquals(other: UIntArray?): Boolean = null!!
public fun UIntArray?.contentHashCode(): Int = null!!
public fun UIntArray?.contentToString(): String = null!!
public fun UIntArray.reversedArray(): UIntArray = null!!
public fun UIntArray.sort(): Unit = null!!
public fun UIntArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun UIntArray.sortDescending(): Unit = null!!
public fun UIntArray.sortedArray(): UIntArray = null!!
public fun UIntArray.sortedArrayDescending(): UIntArray = null!!
public fun UIntArray.binarySearch(element: UInt, fromIndex: Int = 0, toIndex: Int = size): Int = null!!

public infix fun ULongArray?.contentEquals(other: ULongArray?): Boolean = null!!
public fun ULongArray?.contentHashCode(): Int = null!!
public fun ULongArray?.contentToString(): String = null!!
public fun ULongArray.reversedArray(): ULongArray = null!!
public fun ULongArray.sort(): Unit = null!!
public fun ULongArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit = null!!
public fun ULongArray.sortDescending(): Unit = null!!
public fun ULongArray.sortedArray(): ULongArray = null!!
public fun ULongArray.sortedArrayDescending(): ULongArray = null!!
public fun ULongArray.binarySearch(element: ULong, fromIndex: Int = 0, toIndex: Int = size): Int = null!!
