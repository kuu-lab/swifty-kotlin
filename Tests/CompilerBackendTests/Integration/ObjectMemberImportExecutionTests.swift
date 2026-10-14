@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ObjectMemberImportExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func objectMemberImportsPreserveDispatchAndInitialization(useLibrary: Bool, optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        let stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let owner = """
        package sample
        object Owner {
            private var count: Int = 40
            private fun hidden(): Int = count
            fun compare(a: Any?, b: Any?): Boolean = a === b
            fun next(): Int { count += 1; return count }
            fun self(): Any = this
        }
        object First { fun choose(value: Int): Int = value + 1 }
        object Second { fun choose(value: String): String = value }
        class Box { companion object { fun self(): Any = this } }
        """
        let usage = """
        import sample.Owner
        import sample.Owner.compare
        import sample.Owner.compare as compareValues
        import sample.Owner.next as nextValue
        import sample.Owner.self as ownerValue
        import sample.First.choose
        import sample.Second.choose
        import sample.First.choose as selectFirst
        import sample.Second.choose as selectSecond
        import sample.Box.Companion.self as companionValue

        fun same(a: Any?, b: Any?): Boolean = compareValues(a, b)
        fun String.fromExtension(): Boolean = ownerValue() === Owner
        class Reader { fun fromMember(): Boolean = ownerValue() === Owner }
        class Companion {
            fun String.read(): Boolean = companionValue() === sample.Box.Companion
            fun run(): Boolean = "receiver".read()
        }
        fun main() {
            println(nextValue())
            println(nextValue())
            println(Owner.next())
            println(same(null, null))
            println(compare(Owner, null))
            println(Owner.compare(Owner, Owner))
            println("receiver".fromExtension())
            println(Reader().fromMember())
            println(choose(1))
            println(choose("direct"))
            println(selectFirst(2))
            println(selectSecond("alias"))
            println(Companion().run())
        }
        """
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ownerPath = directory.appendingPathComponent("Owner.kt")
        let mainPath = directory.appendingPathComponent("Main.kt")
        try owner.write(to: ownerPath, atomically: true, encoding: .utf8)
        try usage.write(to: mainPath, atomically: true, encoding: .utf8)
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let libraryBase = directory.appendingPathComponent("owner")
        if useLibrary {
            let options = CompilerOptions(
                moduleName: "ObjectMemberOwner", inputs: [ownerPath.path], outputPath: libraryBase.path,
                emit: .library, target: TargetTriple.hostDefault(), optLevel: level,
                includeStdlib: false, allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            for importDirective in [
                "import sample.Owner.hidden",
                "import sample.Owner.hidden as hiddenValue",
                "import sample.Owner.*",
            ] {
                let negativePath = directory.appendingPathComponent("Rejected.kt")
                let name = importDirective.contains("as hiddenValue") ? "hiddenValue" : "hidden"
                try "\(importDirective)\nfun read(): Int = \(name)()\n"
                    .write(to: negativePath, atomically: true, encoding: .utf8)
                let ctx = CompilerTestSupport.makeCompilationContext(
                    inputs: [negativePath.path],
                    searchPaths: [libraryBase.appendingPathExtension("kklib").path],
                    includeStdlib: false, allowDefaultStdlibLibrary: false
                )
                try runSema(ctx)
                #expect(ctx.diagnostics.hasError, "Expected rejected import: \(importDirective)")
                if importDirective.hasSuffix(".*") {
                    assertHasDiagnostic("KSWIFTK-SEMA-0027", in: ctx)
                }
            }
        }
        let executable = directory.appendingPathComponent("app")
        let options = CompilerOptions(
            moduleName: "ObjectMemberConsumer",
            inputs: useLibrary ? [mainPath.path] : [ownerPath.path, mainPath.path],
            outputPath: executable.path, emit: .executable,
            searchPaths: useLibrary ? [libraryBase.appendingPathExtension("kklib").path] : [],
            target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "41\n42\n43\ntrue\nfalse\ntrue\ntrue\ntrue\n2\ndirect\n3\nalias\ntrue\n")
    }
}
