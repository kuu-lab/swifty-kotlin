#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func numericModMatchesKotlin(mode: EmitMode) throws {
        try assertJVM(
            try diffCaseSource("jvm_runtime_numeric_mod.kt", file: #filePath),
            "2\n1\n-2\n-2\nuser:5\n43\n83\n0\nzero divisor\nInfinity\n-Infinity\n1.0\n-Infinity\ntrue\nInfinity\ntrue\ntrue\nInfinity\n",
            mode: mode
        )
    }
}
#endif
