@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendSystemTimingCompatibilityTests {
    @Test(arguments: [false, true])
    func supportedMeasurementsStillExecute(artifact: Bool) throws {
        let source = """
        import kotlin.system.measureTimeMillis
        import kotlin.system.measureNanoTime
        fun main() {
            var count = 0
            val millis = measureTimeMillis { count += 1 }
            val nanos = measureNanoTime { count += 2 }
            println(millis >= 0)
            println(nanos >= 0)
            println(count)
        }
        """
        try assertKotlinOutput(
            source, moduleName: "SystemTimingCompatibility", expected: "true\ntrue\n3\n",
            allowDefaultStdlibLibrary: artifact
        )
    }
}
