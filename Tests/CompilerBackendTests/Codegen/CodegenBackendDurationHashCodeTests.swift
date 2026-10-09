#if canImport(Testing)
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendDurationHashCodeTests {
    @Test
    func testDurationHashCodeAgreesAcrossTypedBoxedAndGenericPaths() throws {
        let source = """
        import kotlin.time.Duration
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.Duration.Companion.seconds

        fun <T> genericHash(x: T): Int = x.hashCode()

        fun main() {
            val d = 5.seconds
            println(d.hashCode())
            println((d as Any).hashCode())
            println(genericHash(d))

            val nullable: Duration? = d
            println(nullable?.hashCode())

            println(0.seconds.hashCode())
            println(1.nanoseconds.hashCode())
            println((1.nanoseconds as Any).hashCode())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DurationHashCode",
            expected: """
            1410065410
            1410065410
            1410065410
            1410065410
            0
            2
            2
            """ + "\n",
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
