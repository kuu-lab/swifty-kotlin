#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func iterableFirstPredicatePreservesInlineAndFailureContracts(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("iterableFirstPredicateContracts.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("iterableFirstPredicateContracts.out"), encoding: .utf8)
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }

    @Test
    func iterableFirstPredicateExposesTheOfficialJavaABI() throws {
        try withWorkspace { root in
            let library = try ownStdlibLibrary()
            try """
            import java.util.Arrays;
            import kotlin.jvm.functions.Function1;
            public class FirstConsumer {
                public static void main(String[] args) {
                    Function1<Integer, Boolean> match = value -> value == 2;
                    System.out.println(kotlin.collections.CollectionsKt.first(Arrays.asList(1, 2, 3), match));
                }
            }
            """.write(to: root.appendingPathComponent("FirstConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", library.path, "FirstConsumer.java"], root: root)
            let result = try java(["-cp", root.path + ":" + library.path, "FirstConsumer"])
            #expect(result.stdout == "2\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
