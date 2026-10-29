@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2294: default-valued stores must not overwrite writes made by a
    /// virtual call from the superclass constructor.
    @Test(arguments: [0, 2])
    func testDefaultFieldInitializersPreserveSuperclassVirtualWrites(
        optimization: Int
    ) throws {
        let stdlib = try testStdlibArtifactPath()
        let optLevel: OptimizationLevel = optimization == 0 ? .O0 : .O2
        let source = """
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
                xShort = 3.toShort()
                xInt = 4
                xLong = 5L
                xFloat = 6.0f
                xDouble = 7.0
                xRef = placeHolder
            }

            var xBool = false
            var xByte = 0.toByte()
            var xChar = 0.toChar()
            var xShort = 0.toShort()
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

        fun box(): String {
            val d = Derived()
            if (d.xBool != true) return "fail Bool"
            if (d.xByte != 1.toByte()) return "fail Byte"
            if (d.xChar != 2.toChar()) return "fail Char"
            if (d.xShort != 3.toShort()) return "fail Short"
            if (d.xInt != 4) return "fail Int"
            if (d.xLong != 5L) return "fail Long"
            if (d.xFloat != 6.0f) return "fail Float"
            if (d.xDouble != 7.0) return "fail Double"
            if (d.xRef != placeHolder) return "fail Ref"
            if (d.xNull != null) return "fail nullable reference default"
            return "OK"
        }

        fun main() {
            print(box())
            if (NonDefaultDerived().value != 42) print("fail non-default initializer")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let context = CompilationContext(
                options: CompilerOptions(
                    moduleName: "KUU2294DefaultFieldInitializers",
                    inputs: [path],
                    outputPath: output,
                    emit: .executable,
                    target: defaultTargetTriple(),
                    optLevel: optLevel,
                    includeStdlib: false,
                    stdlibLibraryPath: stdlib,
                    allowDefaultStdlibLibrary: false
                ),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToLowering(context)
            try assertNoDiagnosticErrors(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(
                result.stdout == "OK",
                "Unexpected output at O\(optimization): \(String(reflecting: result.stdout))"
            )
        }
    }
}
