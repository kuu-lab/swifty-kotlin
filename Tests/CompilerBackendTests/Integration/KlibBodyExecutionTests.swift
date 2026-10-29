@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// Executes bodies deserialized from a real Kotlin/Native `.klib`: source
/// code calls `demo.add` (primitive intrinsic inside a serialized body) and
/// `Greeter.greet()` (ctor field init + property getter + string concat).
@Suite
struct KlibBodyExecutionTests {
    private static var fixtureDirectory: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Integration/
            .deletingLastPathComponent() // CompilerBackendTests/
            .deletingLastPathComponent() // Tests/
            .appendingPathComponent("CompilerCoreTests/Klib/Fixtures")
            .path
    }

    @Test
    func executesImportedKlibBodies() throws {
        let fixtureKlib = Self.fixtureDirectory + "/demo.klib"
        guard FileManager.default.fileExists(atPath: fixtureKlib) else { return }

        let fm = FileManager.default
        let sourcePath = fm.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).kt").path
        let outputBase = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer {
            try? fm.removeItem(atPath: sourcePath)
            try? fm.removeItem(atPath: outputBase)
        }
        try """
        import demo.add
        import demo.Greeter

        fun main() {
            println(add(3, 4))
            val g = Greeter("Bob")
            println(g.greet())
        }
        """.write(toFile: sourcePath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KlibBodyExec",
            inputs: [sourcePath],
            outputPath: outputBase,
            emit: .executable,
            searchPaths: [Self.fixtureDirectory],
            target: defaultTargetTriple()
        )
        let result = makeTestDriver().runForTesting(options: options)
        try assertCompilationSucceeded(result, context: "klib body compilation")

        let runResult = try CommandRunner.run(executable: outputBase, arguments: [])
        let normalized = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
        #expect(normalized == "7\nHello, Bob\n")
    }

    /// KUU-2294: imported default-valued fields must retain writes from a
    /// superclass constructor's virtual dispatch.
    @Test(arguments: [0, 2])
    func importedKlibDefaultFieldInitializersPreserveVirtualWrites(optimization: Int) throws {
        let librarySource = """
        package defaultfields

        open class Base {
            open fun setup() {}
            init { setup() }
        }

        val placeHolder = Any()

        class Derived : Base {
            constructor() : super()

            override fun setup() {
                xBool = true
                xByte = 1.toByte()
                xChar = 2.toChar()
                xShort = 3
                xInt = 4
                xLong = 5L
                xFloat = 6.0f
                xDouble = 7.0
                xRef = placeHolder
            }

            var xBool: Boolean = false
            var xByte = 0.toByte()
            var xChar = 0.toChar()
            var xShort: Short = 0
            var xInt = 0
            var xLong = 0L
            var xFloat = 0.0f
            var xDouble = 0.0
            var xRef: Any? = null
            var xNull: Any? = null
        }

        class NonDefaultDerived : Base() {
            override fun setup() { value = 1 }
            var value = 42
        }
        """

        try withCompiledLibrary(source: librarySource, moduleName: "KUU2294DefaultFieldInitializers") { library in
            try withTemporaryFile(contents: """
            import defaultfields.Derived
            import defaultfields.NonDefaultDerived
            import defaultfields.placeHolder

            fun main() {
                val d = Derived()
                if (d.xBool != true) { println("fail Bool"); return }
                if (d.xByte != 1.toByte()) { println("fail Byte"); return }
                if (d.xChar != 2.toChar()) { println("fail Char"); return }
                if (d.xShort != 3.toShort()) { println("fail Short"); return }
                if (d.xInt != 4) { println("fail Int"); return }
                if (d.xLong != 5L) { println("fail Long"); return }
                if (d.xFloat != 6.0f) { println("fail Float"); return }
                if (d.xDouble != 7.0) { println("fail Double"); return }
                if (d.xRef != placeHolder) { println("fail Ref"); return }
                if (d.xNull != null) { println("fail nullable reference default"); return }
                if (NonDefaultDerived().value != 42) { println("fail non-default initializer"); return }
                println("OK")
            }
            """) { sourcePath in
                let outputBase = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputBase) }
                let options = CompilerOptions(
                    moduleName: "KlibDefaultFieldInitializers",
                    inputs: [sourcePath],
                    outputPath: outputBase,
                    emit: .executable,
                    searchPaths: [library],
                    target: defaultTargetTriple(),
                    optLevel: optimization == 0 ? .O0 : .O2
                )
                let result = makeTestDriver().runForTesting(options: options)
                try assertCompilationSucceeded(result, context: "KUU-2294 imported Klib body compilation")

                let runResult = try CommandRunner.run(executable: outputBase, arguments: [])
                #expect(runResult.exitCode == 0, "\(runResult.stderr)")
                #expect(runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "OK\n")
            }
        }
    }
}
