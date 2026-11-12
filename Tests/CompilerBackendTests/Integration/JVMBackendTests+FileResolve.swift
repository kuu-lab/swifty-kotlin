#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func fileResolveMatchesKotlincAndOwnStdlib() throws {
        let source = """
        import java.io.File

        fun main() {
            println(File("parent").resolve("child").getPath())
            println(File("parent/").resolve("child").getPath())
            println(File("/tmp/parent").resolve("/abs").getPath())
            println(File("parent").resolve("").getPath())
            println(File("parent").resolve("../child").getPath())
            println(File("parent").resolve(File("child")).getPath())
        }
        """
        try withWorkspace { root in
            try runRuntimeParity(
                source,
                expected: "parent/child\nparent/child\n/abs\nparent\nparent/../child\nparent/child\n",
                mode: .jvmJar,
                root: root
            )
        }
    }
}
#endif
