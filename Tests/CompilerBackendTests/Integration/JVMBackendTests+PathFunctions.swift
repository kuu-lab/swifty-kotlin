#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func nioPathHelpersUseJavaFileSystem() throws {
        try withWorkspace { root in
            let file = root.appendingPathComponent("present.txt")
            let link = root.appendingPathComponent("link.txt")
            try "content".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            try runM11("""
            import java.nio.file.LinkOption
            import kotlin.io.path.Path
            import kotlin.io.path.absolute
            import kotlin.io.path.isRegularFile
            import kotlin.io.path.notExists

            fun main() {
                val file = Path("\(file.path)")
                val link = Path("\(link.path)")
                println(file.absolute() == file)
                val relative = Path("present.txt")
                println(relative.absolute() != relative)
                println(file.isRegularFile())
                println(link.isRegularFile())
                println(link.isRegularFile(LinkOption.NOFOLLOW_LINKS))
                println(Path("\(root.appendingPathComponent("absent.txt").path)").notExists())
            }
            """, expected: "true\ntrue\ntrue\ntrue\nfalse\ntrue\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
