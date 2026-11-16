#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledListAndIterableIndexOfUsesOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            public final class SearchProbe {
                public static void main(String[] args) {
                    java.util.List<String> list = java.util.Arrays.asList("first", null, "first");
                    System.out.println(kotlin.collections.CollectionsKt.indexOf(list, "first"));
                    System.out.println(kotlin.collections.CollectionsKt.indexOf(list, null));
                    Iterable<String> iterable = list::iterator;
                    System.out.println(kotlin.collections.CollectionsKt.indexOf(iterable, "missing"));
                    System.out.println(kotlin.collections.CollectionsKt.indexOf(iterable, null));
                }
            }
            """.write(to: root.appendingPathComponent("SearchProbe.java"), atomically: true, encoding: .utf8)
            let reference = try m11Runtime()
            let compiled = try jvmTool("javac", ["-cp", reference, "SearchProbe.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let official = try java(["-cp", root.path + ":" + reference, "SearchProbe"])
            let candidate = try java(["-cp", root.path + ":" + stdlib.path, "SearchProbe"])
            #expect(candidate.stdout == "0\n1\n-1\n1\n")
            #expect(candidate.stdout == official.stdout)
        }
    }
}
#endif
