// KUU-2904: primitive-array sorted variants must be available from the bundled stdlib.
fun main() {
    println("bca".toCharArray().sorted())
    println("bca".toCharArray().sortedDescending())
    println(charArrayOf('c', 'a').sorted())
    println(charArrayOf('c', 'a').sortedDescending())

    println(byteArrayOf(3, 1).sorted())
    println(byteArrayOf(3, 1).sortedDescending())
    println(shortArrayOf(3, 1).sorted())
    println(shortArrayOf(3, 1).sortedDescending())
    println(intArrayOf(3, 1).sorted())
    println(intArrayOf(3, 1).sortedDescending())
    println(longArrayOf(3L, 1L).sorted())
    println(longArrayOf(3L, 1L).sortedDescending())
    println(floatArrayOf(3.0f, 1.0f).sorted())
    println(floatArrayOf(3.0f, 1.0f).sortedDescending())
    println(doubleArrayOf(3.0, 1.0).sorted())
    println(doubleArrayOf(3.0, 1.0).sortedDescending())

    println(ubyteArrayOf(3u, 1u).sorted())
    println(ubyteArrayOf(3u, 1u).sortedDescending())
    println(ushortArrayOf(3u, 1u).sorted())
    println(ushortArrayOf(3u, 1u).sortedDescending())
    println(uintArrayOf(3u, 1u).sorted())
    println(uintArrayOf(3u, 1u).sortedDescending())
    println(ulongArrayOf(3uL, 1uL).sorted())
    println(ulongArrayOf(3uL, 1uL).sortedDescending())
}
