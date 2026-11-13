#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func resolvesForeignSignaturesAndChecksOnlyDemandedInlineBodies() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let input = root.appendingPathComponent("sample.kt").path
            let source = """
            import dep.Counter as C
            import kotlin.also as inspect

            fun main() {
                val value = C.absent().inspect { println(it == null) }
                println(value == null)
                println(C.twice(21))
                println(C.twice(14L))
            }
            """
            let options = CompilerOptions(
                moduleName: "DemandLoadedLibrary",
                inputs: [input], outputPath: root.appendingPathComponent("out.jar").path,
                emit: .jvmJar, target: .hostDefault(), jvmClasspath: [dependency.path]
            )
            let result = CompilerDriver().runFrontend(
                options: options, inMemorySources: [input: Data(source.utf8)]
            )
            try #require(!result.context.diagnostics.hasError, "\(result.diagnostics.map(\.message))")
            let context = result.context
            let imports = try #require(context.jvmImports)
            let ast = try #require(context.ast)
            let sema = try #require(context.sema)
            let counter = ["dep", "Counter", "Companion"].map(context.interner.intern)
            let absent = try #require(sema.symbols.lookup(fqName: counter + [context.interner.intern("absent")]))
            let unused = try #require(sema.symbols.lookup(fqName: ["dep", "Init", "<init>"].map(context.interner.intern)))
            #expect(imports.methods[absent]?.descriptor == "()Ljava/lang/String;")
            #expect(imports.methods[unused] == nil)

            func blockExpressions(_ name: String) throws -> [ExprID] {
                let fqName = ["kotlin", name].map(context.interner.intern)
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                let id = try #require(sema.bindings.declSymbols.first(where: { $0.value == symbol })?.key)
                guard case let .funDecl(function)? = ast.arena.decl(id),
                      case let .block(expressions, _) = function.body else {
                    Issue.record("Expected a bundled inline block for \(name)")
                    return []
                }
                return expressions
            }
            let also = try blockExpressions("also")
            let apply = try blockExpressions("apply")
            try #require(!also.isEmpty)
            #expect(sema.bindings.exprType(for: also[0]) != nil)
            #expect(apply.isEmpty)

            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: [dependency.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let execution = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + dependency.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "true\ntrue\n42\n42\n")
        }
    }
}
#endif
