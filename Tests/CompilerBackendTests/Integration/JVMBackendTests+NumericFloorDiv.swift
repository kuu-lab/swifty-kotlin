#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func numericFloorDivMatchesKotlin(mode: EmitMode) throws {
        try assertJVM(
            try diffCaseSource("jvm_runtime_numeric_floordiv.kt", file: #filePath),
            "-3\n-3\n2\n-2\n-1\nuser:5\n43\n-2147483648\n-9223372036854775808\nzero divisor\n-3\n-3\nLR-3\n",
            mode: mode
        )
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func numericFloorDivRespectsUserExtension(mode: EmitMode) throws {
        try assertJVM(
            try diffCaseSource("jvm_floordiv_user_extension.kt", file: #filePath),
            "103\n103\n-3\n2\n",
            mode: mode
        )
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func numericFloorDivNamedAndSafeCalls(mode: EmitMode) throws {
        try assertJVM(
            try diffCaseSource("jvm_floordiv_named_safe.kt", file: #filePath),
            "-3\nnull\narg:-3\n",
            mode: mode
        )
    }
}
#endif
