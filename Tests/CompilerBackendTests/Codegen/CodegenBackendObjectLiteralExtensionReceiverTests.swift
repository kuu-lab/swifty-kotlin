#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendObjectLiteralExtensionReceiverTests {
    @Test
    func objectPropertyInitializerUsesEnclosingExtensionReceiver() throws {
        let source = try diffCaseSource(
            "kuu_2110_extension_receiver_object_property_initializer.kt",
            file: #filePath
        )
        try assertKotlinOutput(
            source,
            moduleName: "KUU2110ExtensionReceiverObjectPropertyInitializer",
            expected: "5\n"
        )
    }
}
#endif
