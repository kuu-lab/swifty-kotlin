#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func anonymousObjectsInTopLevelExtensionsUseFacadePackage(mode: EmitMode) throws {
        let runtime = try m11Runtime()
        try withWorkspace { root in
            let source = """
                @file:kotlin.jvm.JvmName("Functions")
                package demo.facade
                interface Action { fun run(): Int }
                fun <T> Array<T>.make(): Action = object : Action { override fun run(): Int = 42 }
                fun String.make(): Action = object : Action { override fun run(): Int = 17 }
                class Owner { fun create(): Action = object : Action { override fun run(): Int = 23 } }
                fun main() {
                    println(arrayOf(1).make().run())
                    println("x".make().run())
                    println(Owner().create().run())
                }
                """
            let result = try compile(source, root: root, mode: mode, classpath: runtime.components(separatedBy: ":"))
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + runtime, "demo.facade.Functions"])
            #expect(execution.exitCode == 0, Comment(rawValue: execution.stderr))
            #expect(execution.stdout == "42\n17\n23\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
