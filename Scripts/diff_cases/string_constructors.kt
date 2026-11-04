fun describeCodePoints(build: () -> String): String {
    return try {
        val text = build()
        "ok:" + text.length + ":" + text
    } catch (e: java.lang.StringIndexOutOfBoundsException) {
        "SIOOBE:" + e.message
    } catch (e: IllegalArgumentException) {
        "IAE:" + e.message
    }
}

fun main() {
    val bytes = byteArrayOf(65, 66, 67)
    val chars = charArrayOf('A', 'B', 'C')
    println(String(bytes))
    println(String(bytes, Charsets.UTF_8))
    println(String(byteArrayOf()).length)
    println(String(chars))
    println(String(chars, 1, 2))

    // String(IntArray, Int, Int) — JVM String(int[], int, int) code points.
    val codePoints = intArrayOf(0x41, 0x42, 0x1F600, 0xE9, 0x10000, 0x10FFFF)
    println(describeCodePoints { String(codePoints, 0, codePoints.size) })
    println(describeCodePoints { String(codePoints, 1, 3) })
    println(describeCodePoints { String(codePoints, 2, 0) })
    println(describeCodePoints { String(codePoints, codePoints.size, 0) })
    println(describeCodePoints { String(codePoints, codePoints.size + 1, 0) })
    println(describeCodePoints { String(codePoints, -1, 2) })
    println(describeCodePoints { String(codePoints, 0, -1) })
    println(describeCodePoints { String(codePoints, 4, 3) })
    println(describeCodePoints { String(codePoints, 0, 7) })
    println(describeCodePoints { String(intArrayOf(65, -1), 0, 2) })
    println(describeCodePoints { String(intArrayOf(65, 0x110000), 0, 2) })
    println(describeCodePoints { String(intArrayOf(0xD800), 0, 1) })
    println(describeCodePoints { String(intArrayOf(Int.MIN_VALUE), 0, 1) })
    println(describeCodePoints { String(intArrayOf(), 0, 0) })
    val emoji = String(intArrayOf(0x1F600), 0, 1)
    println(emoji.length)
    println(emoji[0].code.toString() + "," + emoji[1].code)
    println(emoji.codePointAt(0))
}
