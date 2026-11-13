#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmIntrinsicsStringPlusLinksForPrecompiledConsumers() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.jvm.internal.Intrinsics;

            public final class Driver {
                public static void main(String[] args) {
                    System.out.println(Intrinsics.stringPlus("file:", 42));
                    System.out.println(Intrinsics.stringPlus(null, null));
                    System.out.println(Intrinsics.stringPlus("file:", new Object() {
                        @Override public String toString() { return "name"; }
                    }));
                }
            }
            """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let official = try m11Runtime()
            let compiled = try jvmTool("javac", ["-cp", official, "Driver.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let result = try java(["-Xverify:all", "-cp", root.path + ":" + library.path, "Driver"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "file:42\nnullnull\nfile:name\n")
        }
    }
}
#endif
