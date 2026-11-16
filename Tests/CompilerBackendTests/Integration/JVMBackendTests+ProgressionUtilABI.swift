#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledProgressionLastElementUsesOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            public final class ProgressionProbe {
                public static void main(String[] args) {
                    System.out.println(kotlin.internal.ProgressionUtilKt.getProgressionLastElement(1, 6, 2));
                    System.out.println(kotlin.internal.ProgressionUtilKt.getProgressionLastElement(6, 1, -2));
                    System.out.println(kotlin.internal.ProgressionUtilKt.getProgressionLastElement(-4L, 5L, 3L));
                    System.out.println(kotlin.internal.ProgressionUtilKt.getProgressionLastElement(5L, -4L, -4L));
                    System.out.println(kotlin.internal.ProgressionUtilKt.getProgressionLastElement(5, 3, 2));
                    try { kotlin.internal.ProgressionUtilKt.getProgressionLastElement(1, 2, 0); }
                    catch (IllegalArgumentException ex) { System.out.println(ex.getMessage()); }
                }
            }
            """
            try source.write(to: root.appendingPathComponent("ProgressionProbe.java"), atomically: true, encoding: .utf8)
            let runtime = try m11Runtime()
            let compiled = try jvmTool("javac", ["-cp", runtime, "ProgressionProbe.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let official = try java(["-cp", root.path + ":" + runtime, "ProgressionProbe"])
            let candidate = try java(["-cp", root.path + ":" + stdlib.path, "ProgressionProbe"])
            #expect(candidate.stdout == "5\n2\n5\n-3\n3\nStep is zero.\n")
            #expect(candidate.stdout == official.stdout)
        }
    }
}
#endif
