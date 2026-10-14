import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct SuperRuntimeBridgeArtifactTests {
    @Test(arguments: [false, true], [0, 2])
    func concreteIteratorSuperAndControls(fromSource: Bool, optimization: Int) throws {
        let stdlib = fromSource ? nil : try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        try withTemporaryFile(contents: diffCaseSource("super_iterator_runtime_fallback.kt")) { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let options = CompilerOptions(
                moduleName: "SuperRuntimeBridge", inputs: [path], outputPath: output, emit: .executable,
                target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "7\n7\n9\nfalse\nempty\n")

            // A sole bridge retains its binding and non-abstract runtime contract.
            let bridgeOnly = "class Only : Iterator<Int> { fun fallback(): Int = super.next() }"
            let ctx = CompilerDriver().runFrontend(options: options, inMemorySources: [path: Data(bridgeOnly.utf8)]).context
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let bridge = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterator", "next"].map(ctx.interner.intern)))
            #expect(sema.symbols.symbol(bridge)?.flags.contains(.abstractType) == false)
            #expect(sema.symbols.externalLinkName(for: bridge) == "kk_iterator_next")
            let ast = try #require(ctx.ast)
            let call = try #require(ast.arena.exprs.indices.map { ExprID(rawValue: Int32($0)) }.first {
                guard let range = ast.arena.exprRange($0),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(receiver, _, _, _, _) = ast.arena.expr($0),
                      case .superRef = ast.arena.expr(receiver)
                else { return false }
                return sema.bindings.callBinding(for: $0)?.chosenCallee == bridge
            })
            #expect(sema.bindings.isSuperCallExpr(call))
            try BuildKIRPhase().run(ctx)
            try LoweringPhase().run(ctx)
            let kir = try #require(ctx.kir)
            let fallback = try #require(sema.symbols.lookup(fqName: ["Only", "fallback"].map(ctx.interner.intern)))
            let function = try #require(kir.arena.function(for: fallback))
            #expect(function.body.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, isSuperCall, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == "kk_iterator_next" && isSuperCall
            })

            for ambiguous in [
                "interface Left { fun next(): Int = 1 }; interface Right { fun next(): Int = 2 }; class Both : Left, Right { override fun next(): Int = super.next() }",
                "open class Base { open fun next(): Int = 1 }; interface Right { fun next(): Int = 2 }; class Both : Base(), Right { override fun next(): Int = super.next() }",
            ] {
                let rejected = CompilerDriver().runFrontend(options: options, inMemorySources: [path: Data(ambiguous.utf8)]).context
                let errors = rejected.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(errors.count == 1, "\(errors)")
                #expect(errors.first?.code == "KSWIFTK-SEMA-0056")
            }
        }
    }

    @Test(arguments: [0, 2])
    func importedSourceDefaultsStillCompete(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("Defaults").path
        try """
        package defaults
        interface Left { fun next(): Int = 1 }
        interface Right { fun next(): Int = 2 }
        open class Base : Iterator<Int> {
            override fun hasNext(): Boolean = false
            override fun next(): Int = 3
        }
        """.write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "Defaults", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let consumer = directory.appendingPathComponent("consumer.kt").path
        let options = CompilerOptions(
            moduleName: "Consumer", inputs: [consumer], outputPath: directory.appendingPathComponent("out").path,
            emit: .executable, searchPaths: [library + ".kklib"], target: defaultTargetTriple(),
            optLevel: level, stdlibLibraryPath: stdlib
        )
        for parents in ["Left, Right", "Base(), Right"] {
            let source = "import defaults.*; class Both : \(parents) { override fun next(): Int = super.next() }"
            let ctx = CompilerDriver().runFrontend(options: options, inMemorySources: [consumer: Data(source.utf8)]).context
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0056")
            let sema = try #require(ctx.sema)
            let right = try #require(sema.symbols.lookup(fqName: ["defaults", "Right", "next"].map(ctx.interner.intern)))
            #expect(sema.symbols.symbol(right)?.flags.contains(.importedLibrary) == true)
            #expect(sema.symbols.externalLinkName(for: right) != nil)
            #expect(!sema.symbols.annotations(for: right).contains { KnownCompilerAnnotation.ksSymbolName.matches($0.annotationFQName) })
        }
        try """
        import defaults.*
        class Child : Base(), MutableIterator<Int> {
            override fun next(): Int = super.next()
            override fun remove() {}
        }
        class Qualified : Left, Right {
            override fun next(): Int = super<Left>.next() + super<Right>.next()
        }
        fun main() { println(Child().next()); println(Qualified().next()) }
        """.write(toFile: consumer, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: options.outputPath, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "3\n3\n")
    }
}
