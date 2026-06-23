@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // STDLIB-TEXT-TYPE-008: MatchGroupCollection interface — index access, named access, size
    func testMatchGroupCollectionIndexAccess() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\w+)-(\\\\w+)")
            val m = r.find("hello-world")
            println(m?.groups?.get(0)?.value)
            println(m?.groups?.get(1)?.value)
            println(m?.groups?.get(2)?.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionIndex",
            expected:
                """
                hello-world
                hello
                world
                """ + "\n"
        )
    }

    func testMatchGroupCollectionNamedAccess() throws {
        let source = """
        fun main() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
            val m = r.find("2025-06-09")
            println(m?.groups?.get("year")?.value)
            println(m?.groups?.get("month")?.value)
            println(m?.groups?.get("day")?.value)
            println(m?.groups?.get("missing"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionNamed",
            expected:
                """
                2025
                06
                09
                null
                """ + "\n"
        )
    }

    func testMatchGroupCollectionSize() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\w+)-(\\\\w+)-(\\\\w+)")
            val m = r.find("a-b-c")
            println(m?.groups?.size)
            val r2 = Regex("\\\\w+")
            val m2 = r2.find("hello")
            println(m2?.groups?.size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionSize",
            expected:
                """
                4
                1
                """ + "\n"
        )
    }

    func testMatchGroupCollectionOutOfBoundsReturnsNull() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\d+)")
            val m = r.find("42")
            println(m?.groups?.get(0)?.value)
            println(m?.groups?.get(99))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionOutOfBounds",
            expected:
                """
                42
                null
                """ + "\n"
        )
    }
}

