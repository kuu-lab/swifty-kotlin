#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenCompanionPropertyImportTests {
    @Test(arguments: [false, true])
    func directImportsCallSingletonExtensionGetters(useArtifact: Bool) throws {
        let source = """
        import kotlin.Int.Companion.MAX_VALUE
        import kotlin.Long.Companion.MIN_VALUE as longMin
        import kotlin.time.Duration
        import kotlin.time.Duration.Companion.INFINITE
        import kotlin.time.Duration.Companion.ZERO as zeroDuration

        fun main() {
            println(MAX_VALUE)
            println(longMin)
            println(INFINITE)
            println(zeroDuration)
            println(MAX_VALUE == Int.MAX_VALUE)
            println(INFINITE == Duration.INFINITE)
            println(zeroDuration == Duration.ZERO)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "CompanionPropertyDirectImport",
            expected: "2147483647\n-9223372036854775808\nInfinity\n0s\ntrue\ntrue\ntrue\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
#endif
