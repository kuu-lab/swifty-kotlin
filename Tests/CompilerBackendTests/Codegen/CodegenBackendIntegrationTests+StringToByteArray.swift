// STDLIB-TEXT-FN-092: End-to-end execution tests for String.toByteArray().
// toByteArray() and its charset overload are Kotlin-sourced (kotlin/text/StringEncoding.kt)
// and return an actual ByteArray/ArrayBox, backed by the __kk_string_toByteArray_flat /
// __kk_string_toByteArray_charset_flat runtime bridges in RuntimeStringEncoding.swift.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testCodegenStringToByteArrayNoArg() throws {
        let source = """
        fun main() {
            val bytes = "abc".toByteArray()
            println(bytes.size)
            println(bytes[0])
            println(bytes[1])
            println(bytes[2])
        }
        """
        try assertKotlinOutput(source, moduleName: "StringToByteArrayNoArg", expected: "3\n97\n98\n99\n")
    }

    func testCodegenStringToByteArrayCharsets() throws {
        let source = """
        fun main() {
            val utf8 = "hello".toByteArray(Charsets.UTF_8)
            println(utf8.size)

            val latin1 = "hello".toByteArray(Charsets.ISO_8859_1)
            println(latin1.size)

            val ascii = "hello".toByteArray(Charsets.US_ASCII)
            println(ascii.size)

            // UTF-16BE: 2 bytes per BMP char, no BOM
            val utf16be = "ab".toByteArray(Charsets.UTF_16BE)
            println(utf16be.size)

            // UTF-16LE: 2 bytes per BMP char, no BOM
            val utf16le = "ab".toByteArray(Charsets.UTF_16LE)
            println(utf16le.size)
        }
        """
        try assertKotlinOutput(source, moduleName: "StringToByteArrayCharsets", expected: "5\n5\n5\n4\n4\n")
    }
}

