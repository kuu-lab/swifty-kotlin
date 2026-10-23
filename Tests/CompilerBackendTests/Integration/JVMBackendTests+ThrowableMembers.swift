#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func throwableMembersDelegateToJDK(mode: EmitMode) throws {
        let source = """
        fun main() {
            val exception = Exception("outer", Exception("inner"))
            println(exception.cause?.message)
            println(exception.stackTrace.size > 0)

            exception.addSuppressed(Exception("suppressed"))
            println(exception.suppressed.size)
            println(exception.suppressed[0].message)

            val initialized = Exception("initialized")
            println(initialized.initCause(Exception("init")) === initialized)
            println(initialized.cause?.message)

            try {
                throw Exception("printed")
            } catch (throwable: Exception) {
                throwable.printStackTrace()
            }
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let application = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", application.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "inner\ntrue\n1\nsuppressed\ntrue\ninit\n")
            let stderr = execution.stderr.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(stderr.hasPrefix("java.lang.Exception: printed\n\tat "))
        }
    }
}
#endif
