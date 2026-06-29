@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// STDLIB-IO-PATH-FN-038: kotlin.io.path.Path.useLines codegen tests
extension CodegenBackendIntegrationTests {

    func testCodegenPathUseLinesCount() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_count.txt")
            path.deleteIfExists()
            path.writeText("alpha\\nbeta\\ngamma")

            val count = path.useLines { lines ->
                lines.count()
            }
            println(count)

            path.deleteIfExists()
        }
        """

        try assertKotlinOutput(source, moduleName: "PathUseLinesCount", expected: "3\n")
    }

    func testCodegenPathUseLinesForEach() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_foreach.txt")
            path.deleteIfExists()
            path.writeText("one\\ntwo\\nthree")

            path.useLines { lines ->
                lines.forEach { line -> println(line) }
            }

            path.deleteIfExists()
        }
        """

        try assertKotlinOutput(source, moduleName: "PathUseLinesForEach", expected: "one\ntwo\nthree\n")
    }

    func testCodegenPathUseLinesEmptyFile() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_empty.txt")
            path.deleteIfExists()
            path.writeText("")

            val count = path.useLines { lines ->
                lines.count()
            }
            println(count)

            path.deleteIfExists()
        }
        """

        try assertKotlinOutput(source, moduleName: "PathUseLinesEmpty", expected: "0\n")
    }

    func testCodegenPathUseLinesReturnsList() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_tolist.txt")
            path.deleteIfExists()
            path.writeText("x\\ny\\nz")

            val lines: List<String> = path.useLines { it.toList() }
            println(lines.size)
            lines.forEach { println(it) }

            path.deleteIfExists()
        }
        """

        try assertKotlinOutput(source, moduleName: "PathUseLinesReturnsList", expected: "3\nx\ny\nz\n")
    }
}

