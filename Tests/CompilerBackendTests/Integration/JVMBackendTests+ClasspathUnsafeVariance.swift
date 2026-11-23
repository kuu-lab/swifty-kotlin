#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinUnsafeVarianceMembersPassVarianceCheck() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture

            interface Stack<out E> : Iterable<E> {
                fun push(element: @UnsafeVariance E): Stack<E>
                fun contains(element: @UnsafeVariance E): Boolean
            }

            private class ListStack<E>(private val items: List<E>) : Stack<E> {
                override fun push(element: E): Stack<E> = ListStack(items + element)
                override fun contains(element: E): Boolean = element in items
                override fun iterator(): Iterator<E> = items.iterator()
            }

            fun emptyStack(): Stack<String> = ListStack(emptyList())
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.emptyStack
            fun main() {
                val stack = emptyStack().push("a").push("b")
                println(stack.contains("b"))
                for (item in stack) println(item)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "true\na\nb\n")
        }
    }
}
#endif
