#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func abstractListConcreteMembersDoNotRemainAbstract() throws {
        try withWorkspace { root in
            let source = """
            class Singleton : AbstractList<Int>() {
                override val size: Int get() = 1
                override fun get(index: Int): Int = 42
            }
            fun main() { println(Singleton()[0]) }
            """
            let input = root.appendingPathComponent("abstractList.kt")
            let output = root.appendingPathComponent("abstract-list.jar")
            try source.write(to: input, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: "AbstractListCompleteness",
                inputs: [input.path],
                outputPath: output.path,
                emit: .jvmJar,
                target: .hostDefault(),
                includeJVMRuntime: true
            )
            let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
            try #require(result.exitCode == 0, "\(result.diagnostics.map(\.message))")

            let execution = try java(["-jar", output.path])
            #expect(execution.stdout == "42\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func genuinelyMissingAbstractListAncestorMemberStillErrors() throws {
        try withWorkspace { root in
            let result = try compile("""
            abstract class RequiredBase {
                abstract fun required(): Int
            }
            class Missing : RequiredBase()
            fun main() {}
            """, root: root, mode: .jvmJar)

            #expect(result.0 != 0)
            #expect(result.1.contains {
                $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.message.contains("'required'")
            })
        }
    }
}
#endif
