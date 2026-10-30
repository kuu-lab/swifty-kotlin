#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    /// KUU-3186: the bundled `kotlin.Comparator` declaration erases to
    /// java/util/Comparator and is never lowered into a classfile. Its
    /// abstract member is bound through the JDK import profile, so a SAM
    /// conversion emits a wrapper implementing the real JDK interface.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func bundledKotlinComparatorSAMImplementsJDKInterface(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun describe(c: Comparator<Int>, a: Int, b: Int) = c.compare(a, b)
            fun main() {
                val c = Comparator<Int> { a, b -> b - a }
                println(describe(c, 1, 2))
                println(describe(c, 2, 1))
                println(describe(c, 5, 5))
                val byLength: Comparator<String> = Comparator { a, b -> a.length - b.length }
                println(byLength.compare("ab", "abc"))
                println(byLength.compare("abc", "a"))
            }
            """, expected: "1\n-1\n0\n-1\n2\n", mode: mode, root: root)

            // The generated wrapper implements the erased JDK interface, not
            // the unemitted `kotlin/Comparator` binary name.
            let classes = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let listing = mode == .jvmJar
                ? try jvmTool("jar", ["tf", classes.path], root: root).stdout
                : (try? FileManager.default.contentsOfDirectory(atPath: classes.path))?.joined(separator: "\n") ?? ""
            let samName = listing.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.contains("$SAM") && $0.hasSuffix(".class") }
                .map { String($0.dropLast(".class".count)) }
            let wrapper = try #require(samName, "no $SAM wrapper class in \(listing)")
            let inspection = try javap(["-cp", classes.path, wrapper])
            #expect(inspection.stdout.contains("implements java.util.Comparator"), "\(inspection.stdout)")
        }
    }
}
#endif
