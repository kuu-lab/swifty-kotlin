#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func covariantAbstractInterfaceBridgeDispatchesForExternalImplementor() throws {
        let declarations = """
        interface BridgeRoot { fun produce(): Any }
        interface BridgeChild : BridgeRoot { override fun produce(): String }
        """
        let consumer = """
        import java.lang.invoke.MethodHandles
        import java.lang.invoke.MethodType

        class ExternalBridge : BridgeChild { override fun produce(): String = "covariant" }

        fun main() {
            val bridge = MethodHandles.privateLookupIn(BridgeChild::class.java, MethodHandles.lookup()).findSpecial(
                BridgeChild::class.java, "produce", MethodType.methodType(Any::class.java), BridgeChild::class.java
            )
            println(bridge.bindTo(ExternalBridge()).invokeWithArguments())
        }
        """
        try withWorkspace { root in
            let compiled = try compile(declarations, root: root, mode: .jvmClass)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            try consumer.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            let official = try m11Runtime()
            let reference = try jvmTool("kotlinc", ["hello.kt", "consumer.kt", "-cp", official, "-d", "reference.jar"], root: root)
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let artifact = root.appendingPathComponent("reference.jar").path
            let classes = root.appendingPathComponent("classes").path
            for classpath in [artifact + ":" + official, classes + ":" + artifact + ":" + official] {
                let execution = try java(["-cp", classpath, "ConsumerKt"])
                #expect(execution.exitCode == 0, "\(execution.stderr)")
                #expect(execution.stdout == "covariant\n")
                #expect(execution.stderr.isEmpty)
            }
        }
    }

    @Test
    func officialPropertyAccessorConsumerRunsWithOwnStdlib() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/JVMOwnStdlibInterop/kuu3699PrecompiledConsumer.kt")
        try withWorkspace { root in
            try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("hello.kt"))
            let official = try m11Runtime()
            let library = try ownStdlibLibrary()
            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", official, "-d", "reference.jar"], root: root)
            let consumer = root.appendingPathComponent("reference.jar").path
            let expected = "base-get=3\nzero-get=4\nfinal=5\ninterface-default-getter=5\ninterface-default-setter=6\n"
            for runtime in [official, library.path] {
                let execution = try java(["-cp", consumer + ":" + runtime, "HelloKt"])
                #expect(execution.exitCode == 0, "\(execution.stderr)")
                #expect(execution.stdout == expected)
                #expect(execution.stderr.isEmpty)
            }
        }
    }
}
#endif
