@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LibraryReflectionInitializationTests {
    @Test
    func libraryNominalTypesRegisterReflectionMembers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()

        func compile(_ source: String, module: String, emit: EmitMode, paths: [String] = []) throws -> String {
            let sourcePath = directory.appendingPathComponent(module + ".kt").path
            let outputPath = directory.appendingPathComponent(module).path
            try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: module, inputs: [sourcePath], outputPath: outputPath,
                emit: emit, searchPaths: paths, target: defaultTargetTriple(),
                stdlibLibraryPath: stdlib
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? outputPath + ".kklib" : outputPath
        }

        let library = try compile("""
        package sample
        class Example(val value: Int) { fun greet() = value }
        object O {
            var y: String = ""
            fun objectMember() = y
        }
        interface I {
            var x: Int
            fun interfaceMember(): Int = 1
        }
        class Holder {
            object Nested {
                var value: Int = 0
                fun nestedObjectMember() = value
            }
            interface NestedContract {
                val flag: Boolean
                fun nestedInterfaceMember(): Boolean = true
            }
        }
        """, module: "ReflectionLibrary", emit: .library)
        let executable = try compile("""
        import kotlin.reflect.full.*
        import kotlin.text.StringBuilder
        import sample.Example
        import sample.Holder
        import sample.I
        import sample.O
        fun main() {
            val klass = Example::class
            println(klass.memberFunctions.any { it.name == "greet" })
            println(klass.memberProperties.any { it.name == "value" })
            println(klass.constructors.isNotEmpty())
            val builder = StringBuilder::class
            println(builder.memberFunctions.any { it.name == "append" })
            println(builder.memberProperties.any { it.name == "length" })
            println(builder.constructors.isNotEmpty())

            println(O::class.memberFunctions.any { it.name == "objectMember" })
            println(O::class.memberProperties.any { it.name == "y" })
            println(O::class.members.any { it.name == "y" })
            println(O::class.constructors.isEmpty())

            println(I::class.memberFunctions.any { it.name == "interfaceMember" })
            println(I::class.memberProperties.any { it.name == "x" })
            println(I::class.members.any { it.name == "x" })
            println(I::class.constructors.isEmpty())

            println(Holder.Nested::class.memberFunctions.any { it.name == "nestedObjectMember" })
            println(Holder.Nested::class.memberProperties.any { it.name == "value" })
            println(Holder.Nested::class.members.any { it.name == "value" })
            println(Holder.Nested::class.constructors.isEmpty())

            println(Holder.NestedContract::class.memberFunctions.any { it.name == "nestedInterfaceMember" })
            println(Holder.NestedContract::class.memberProperties.any { it.name == "flag" })
            println(Holder.NestedContract::class.members.any { it.name == "flag" })
            println(Holder.NestedContract::class.constructors.isEmpty())
        }
        """, module: "ReflectionConsumer", emit: .executable, paths: [library])
        let result = try CommandRunner.run(executable: executable, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stdout == String(repeating: "true\n", count: 22))
    }
}
