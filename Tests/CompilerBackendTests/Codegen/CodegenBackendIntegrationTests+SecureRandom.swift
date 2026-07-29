@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // Candidate-only: SecureRandom.getInstance() with no arguments (KSP-467) is a KSwiftK-only
    // convenience overload — real Java/Kotlin's SecureRandom.getInstance always requires an
    // algorithm name argument, so the JVM kotlinc reference can never compile this case (it
    // fails with "none of the following candidates is applicable"). Moved from
    // Scripts/diff_cases/secure_random.kt (DEBT-DIFF-005).
    func testCodegenCompilesSecureRandomNoArgGetInstance() throws {
        let source = """
        import java.security.SecureRandom

        fun main() {
            val sr = SecureRandom.getInstance()

            val buf = ByteArray(8)
            sr.nextBytes(buf)
            println(buf.size == 8)

            val seed = sr.generateSeed(4)
            println(seed.size == 4)

            val sr2 = SecureRandom.getInstance()
            sr2.setSeed(42)
            val buf2a = ByteArray(4)
            sr2.nextBytes(buf2a)

            val sr3 = SecureRandom.getInstance()
            sr3.setSeed(42)
            val buf2b = ByteArray(4)
            sr3.nextBytes(buf2b)

            println(buf2a.toList() == buf2b.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SecureRandomNoArgGetInstance",
            expected:
                """
                true
                true
                true
                """ + "\n"
        )
    }
}
