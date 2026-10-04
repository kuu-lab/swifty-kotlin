#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendKotlinVersionTests {

    @Test
    func testCodegenCompilesKotlinVersionComponents() throws {
        let source = """
        fun main() {
            val short = KotlinVersion(2, 1)
            val full = KotlinVersion(2, 1, 20)
            println(short.patch)
            println(full.major)
            println(full.minor)
            println(full.patch)
        }
        """

        try assertKotlinOutput(source, moduleName: "KotlinVersionComponents", expected: "0\n2\n1\n20\n")
    }

    @Test
    func testCodegenCompilesKotlinVersionComparisonHelpers() throws {
        let source = """
        fun main() {
            val baseline = KotlinVersion(2, 1, 20)
            println(KotlinVersion.CURRENT.isAtLeast(1, 0))
            println(baseline.compareTo(KotlinVersion(2, 1)) > 0)
            println(baseline < KotlinVersion(2, 2, 0))
            println(baseline.isAtLeast(2, 1, 21))
        }
        """

        try assertKotlinOutput(source, moduleName: "KotlinVersionComparisonHelpers", expected: "true\ntrue\ntrue\nfalse\n")
    }
}
#endif
