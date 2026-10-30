@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct JavaThreadLocalTests {
    // Declaration contracts are owned by DataFlow; end-to-end body and
    // dispatch behavior is covered by the backend source/artifact matrix.
    @Test func sourceBackedJavaSignatures() throws {
        try withTemporaryFile(contents: "fun main() { val local = ThreadLocal<String>() }") { path in
            let ctx = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: false)
            try runFrontend(ctx)
            try DataFlowSemaPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let owner = try #require(sema.symbols.lookup(fqName: ["java", "lang", "ThreadLocal"].map(ctx.interner.intern)))
            #expect(sema.symbols.symbol(owner)?.flags.contains(.openType) == true)
            #expect(sema.symbols.symbol(owner)?.flags.contains(.synthetic) == false)
            for (name, visibility) in [("initialValue", Visibility.protected), ("get", .public)] {
                let symbol = try #require(sema.symbols.lookup(fqName: ["java", "lang", "ThreadLocal", name].map(ctx.interner.intern)))
                #expect(sema.symbols.symbol(symbol)?.visibility == visibility)
                let declaration = try #require(sema.symbols.symbol(symbol))
                let checker = VisibilityChecker(symbols: sema.symbols)
                #expect(checker.isAccessible(
                    declaration, fromFile: FileID(rawValue: 0), enclosingClass: nil
                ) == (visibility == .public))
                #expect(checker.isAccessible(
                    declaration, fromFile: FileID(rawValue: 0), enclosingClass: owner
                ))
                #expect(sema.symbols.symbol(symbol)?.flags.contains(.openType) == true)
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sema.types.nullability(of: signature.returnType) == .platformType)
            }
        }
    }

    @Test(arguments: [
        ("class Local : ThreadLocal<String>() { override fun initialValue(): Int = 1 }", "KSWIFTK-SEMA-OVERRIDE-RETURN"),
        ("class Local : ThreadLocal<String>() { private override fun initialValue(): String = \"bad\" }", "KSWIFTK-SEMA-VISIBILITY"),
    ])
    func invalidOverridesAreRejected(source: String, diagnosticCode: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: false)
            try runFrontend(ctx)
            try? DataFlowSemaPhase().run(ctx)
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == diagnosticCode
            }, "Expected \(diagnosticCode), got: \(ctx.diagnostics.diagnostics)")
        }
    }
    @Test func userDeclarationKeepsNullableResults() throws {
        let source = """
        package java.lang
        class ThreadLocal<T> {
            fun get(): T? = null
            fun initialValue(): T? = null
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false
            )
            try runFrontend(ctx)
            try DataFlowSemaPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            for name in ["get", "initialValue"] {
                let symbol = try #require(sema.symbols.lookup(
                    fqName: ["java", "lang", "ThreadLocal", name].map(ctx.interner.intern)
                ))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sema.types.nullability(of: signature.returnType) == .nullable)
            }
        }
    }

    @Test func importedUserDeclarationKeepsNullableResults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        { "formatVersion": 1, "moduleName": "UserThreadLocal", "metadata": "metadata.bin" }
        """.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try """
        symbols=3
        class _ fq=java.lang.ThreadLocal schema=v1
        function _ fq=java.lang.ThreadLocal.get schema=v1 arity=0 sig=F0<Q<T0>>
        function _ fq=java.lang.ThreadLocal.initialValue schema=v1 arity=0 sig=F0<Q<T0>>
        """.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path], searchPaths: [directory.path],
                includeStdlib: false, allowDefaultStdlibLibrary: false
            )
            try runFrontend(ctx)
            try DataFlowSemaPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            for name in ["get", "initialValue"] {
                let symbol = try #require(sema.symbols.lookup(
                    fqName: ["java", "lang", "ThreadLocal", name].map(ctx.interner.intern)
                ))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sema.types.nullability(of: signature.returnType) == .nullable)
            }
        }
    }
}
