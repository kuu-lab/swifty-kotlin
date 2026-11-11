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
            import java.nio.file.Path as NioPath
            import kotlin.io.path.Path
            import kotlin.io.path.absolute
            import kotlin.io.path.isRegularFile
            import kotlin.io.path.notExists

            fun main() {
                val file = Path("\(file.path)")
                val link = Path("\(link.path)")
                val joined: NioPath = Path("\(root.path)", "present.txt")
                println(joined == file)
                println(Path("\(root.path)", *arrayOf("present.txt")) == file)
                println(file.absolute() == file)
                val relative = Path("present.txt")
                println(relative.absolute() != relative)
                val create: (String) -> NioPath = ::Path
                val absolute: (NioPath) -> NioPath = NioPath::absolute
                println(absolute(create("present.txt")) == relative.absolute())
                println(file.isRegularFile())
                println(link.isRegularFile())
                println(link.isRegularFile(LinkOption.NOFOLLOW_LINKS))
                println(Path("\(root.appendingPathComponent("absent.txt").path)").notExists())
            }
            """, expected: "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
