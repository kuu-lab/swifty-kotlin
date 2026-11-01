#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibAnyConstructorBuildsJavaLangObject(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            class Holder(val owner: Any?) {
                fun ownedBy(candidate: Any): Boolean = owner == candidate
            }
            fun same(left: Any?, right: Any): Boolean = left == right
            fun main() {
                val first = Any()
                val second = Any()
                println(first == second)
                println(same(first, first))
                println(same(null, Any()))
                println(Holder(first).ownedBy(first))
                println(Holder(null).ownedBy(Any()))
                println(first.hashCode() == first.hashCode())
                println(listOf<Any>(Any(), "s").size)
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "false\ntrue\nfalse\ntrue\nfalse\ntrue\n2\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
