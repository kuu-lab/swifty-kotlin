#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    // KUU-1397: String.toCharArray(destination, destinationOffset, startIndex,
    // endIndex) — the kotlin.text destination-copying overload (since Kotlin
    // 2.0). startIndex > endIndex follows Kotlin/Native checkBoundsIndexes
    // semantics (IllegalArgumentException).
    @Test(arguments: [true, false])
    func testStringToCharArrayDestination(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            private fun codesOf(array: CharArray): String {
                val sb = StringBuilder()
                var index = 0
                while (index < array.size) {
                    if (index > 0) sb.append(',')
                    sb.append(array[index].code)
                    index++
                }
                return sb.toString()
            }

            fun main() {
                val dest = CharArray(5)
                val returned = "abc".toCharArray(dest, 1)
                println(codesOf(dest))
                println(returned === dest)
                println(codesOf("abcdef".toCharArray(CharArray(8), 1, 2, 4)))
                println(codesOf("abcdef".toCharArray(CharArray(6))))
                try {
                    "abc".toCharArray(CharArray(4), 0, 0, 9)
                } catch (e: IndexOutOfBoundsException) {
                    println("ioobe-end")
                }
                try {
                    "abc".toCharArray(CharArray(4), 3, 0, 2)
                } catch (e: IndexOutOfBoundsException) {
                    println("ioobe-fit")
                }
                try {
                    "abc".toCharArray(CharArray(4), 0, 2, 1)
                } catch (e: IllegalArgumentException) {
                    println("iae-range")
                }
            }
            """,
            expectedOutput: "0,97,98,99,0\ntrue\n0,99,100,0,0,0,0,0\n97,98,99,100,101,102\nioobe-end\nioobe-fit\niae-range\n",
            moduleName: "StringToCharArrayDestination",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
