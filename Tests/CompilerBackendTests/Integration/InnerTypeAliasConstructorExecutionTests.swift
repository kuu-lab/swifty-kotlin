@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct InnerTypeAliasConstructorExecutionTests {
    private let expectedOutput = "OK\ndirect\ngeneric\nalias2\nalias3\ncallable\ntop-level\n"

    @Test(arguments: [0, 2])
    func sourceStdlibResolvesInnerTypeAliasConstructors(optimization: Int) throws {
        try compileAndRun(optimization: optimization, stdlib: nil)
    }

    @Test(arguments: [0, 2])
    func freshKklibResolvesInnerTypeAliasConstructors(optimization: Int) throws {
        try compileAndRun(
            optimization: optimization,
            stdlib: try StdlibArtifactRegressionTests.buildStdlibArtifact()
        )
    }

    private func compileAndRun(optimization: Int, stdlib: String?) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourcePath = directory.appendingPathComponent("inner_typealias_constructor.kt")
        try source.write(to: sourcePath, atomically: true, encoding: .utf8)
        let outputPath = directory.appendingPathComponent("program").path
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let options = CompilerOptions(
            moduleName: "KUU2206InnerTypeAliasO\(optimization)",
            inputs: [sourcePath.path],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: level,
            includeStdlib: stdlib == nil,
            stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: false
        )

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stdout == expectedOutput)
    }

    private let source = """
    class Outer { inner class Child(val value: String) }
    typealias ChildAlias = Outer.Child

    class Foo<T> {
        inner class Inner(val p: String)
        inner class Inner2<T2>(val p: String)
    }
    typealias InnerAlias<K> = Foo<K>.Inner
    typealias InnerAlias2<K, K2> = Foo<K>.Inner2<K2>
    typealias InnerAlias3<K, K2> = Foo<K2>.Inner2<K>

    class Plain(val value: String)
    typealias PlainAlias = Plain

    fun main() {
        val outer = Outer()
        println(outer.ChildAlias("OK").value)
        println(outer.Child("direct").value)

        val foo = Foo<String>()
        println(foo.InnerAlias("generic").p)
        println(foo.InnerAlias2<String, Int>("alias2").p)
        println(foo.InnerAlias3<Int, String>("alias3").p)
        val make = Foo<String>::InnerAlias
        println(make(foo, "callable").p)

        println(PlainAlias("top-level").value)
    }
    """
}
