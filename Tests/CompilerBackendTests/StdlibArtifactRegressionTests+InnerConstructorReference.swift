@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {
    /// KUU-2455: a bound inner-constructor reference captures its outer instance once.
    @Test(arguments: [true, false], [0, 2])
    func testBoundInnerConstructorReferenceThroughSourceAndFreshArtifact(
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        open class A(val prefix: String) {
            inner class I(val suffix: String) { fun result(): String = prefix + ":" + suffix }
        }
        class B(prefix: String) : A(prefix)
        var ownerCreations = 0
        fun makeOwner(): B {
            ownerCreations += 1
            return B("outer")
        }
        class SimpleOuter { inner class Empty { fun value(): String = "OK" } }
        abstract class OriginalA {
            inner class InnerInA { fun returnOk(): String = "OK" }
        }
        class OriginalB : OriginalA()
        fun originalBox(a: OriginalA): String {
            if (a is OriginalB) {
                val factory = a::InnerInA
                return factory().returnOk()
            }
            return "error"
        }

        fun main() {
            val factory: (String) -> A.I = makeOwner()::I
            println(factory("one").result())
            println(factory("two").result())
            println(ownerCreations)
            val zeroArgumentFactory: () -> SimpleOuter.Empty = SimpleOuter()::Empty
            println(zeroArgumentFactory().value())
            println(originalBox(OriginalB()))
        }
        """
        let input = directory.appendingPathComponent("bound_inner_constructor_reference.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let output = directory.appendingPathComponent("program").path
        let options = CompilerOptions(
            moduleName: "KUU2455BoundInnerConstructorReference",
            inputs: [input.path],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: !fromSource
        )

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stdout == "outer:one\nouter:two\n1\nOK\nOK\n")
    }

    /// KUU-2343: unbound inner-constructor references preserve the outer
    /// instance as the first function argument through default and fresh artifacts.
    @Test(arguments: [true, false], [0, 2])
    func testUnboundInnerConstructorReferenceThroughDefaultAndFreshArtifact(
        useDefaultStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        TestStdlibCache.shared.prepare()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        class Sample(val prefix: String) {
            inner class SS(val text: String) { fun value(): String = prefix + ":" + text }
            class Nested(val text: String)
        }
        class Plain(val text: String)

        fun main() {
            val make: (Sample, String) -> Sample.SS = Sample::SS
            val lambda: (Sample, String) -> Sample.SS = { outer, text -> outer.SS(text) }
            val nested: (String) -> Sample.Nested = Sample::Nested
            val topLevel: (String) -> Plain = ::Plain
            println(make(Sample("outer"), "inner").value())
            println(lambda(Sample("lambda-outer"), "lambda").value())
            println(nested("nested").text)
            println(topLevel("top-level").text)
        }
        """
        let input = directory.appendingPathComponent("inner_constructor_reference.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let artifactPath = useDefaultStdlibLibrary ? nil : try Self.buildStdlibArtifact()
        let output = directory.appendingPathComponent("program").path
        let options = CompilerOptions(
            moduleName: "KUU2343InnerConstructorReference",
            inputs: [input.path],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: useDefaultStdlibLibrary
        )

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stdout == "outer:inner\nlambda-outer:lambda\nnested\ntop-level\n")
    }
}
