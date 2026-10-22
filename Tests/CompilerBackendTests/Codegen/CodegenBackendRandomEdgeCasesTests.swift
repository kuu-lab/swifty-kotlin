#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendRandomEdgeCasesTests {

    @Test
    func testCodegenRandomAsKotlinRandom() throws {
        let source = """
        import java.util.Random as JavaRandom
        import kotlin.random.Random
        import kotlin.random.asKotlinRandom

        fun main() {
            val r1: Random = JavaRandom(42).asKotlinRandom()
            val r2: Random = JavaRandom(42).asKotlinRandom()

            println(r1.nextInt(100) == r2.nextInt(100))
        }
        """

        try assertKotlinOutput(source, moduleName: "RandomAsKotlinRandom", expected: "true\n")
    }

    @Test
    func testCodegenRandomAsJavaRandom() throws {
        let source = """
        import kotlin.random.Random
        import kotlin.random.asJavaRandom

        fun main() {
            val javaRandom: java.util.Random = Random(42).asJavaRandom()
            println("ok")
        }
        """

        try assertKotlinOutput(source, moduleName: "RandomAsJavaRandom", expected: "ok\n")
    }

    @Test
    func testCodegenJavaUtilRandomNoArgAndInstanceMethods() throws {
        let source = """
        import java.util.Random

        fun main() {
            println(Random().nextInt(100) in 0..99)
            val r = Random(42)
            println(r.nextInt(100))
            println(r.nextInt(100))
            println(Random(42).nextInt())
            println(Random(42L).nextLong())
            println(Random(42).nextDouble())
            println(Random(42).nextBoolean())
            println(Random(42).nextInt(5, 10))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "JavaUtilRandomMembers",
            expected: "true\n30\n63\n-1170105035\n-5025562857975149833\n0.7275636800328681\ntrue\n5\n"
        )
    }
}
#endif
