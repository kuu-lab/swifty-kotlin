#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

@Suite
struct FullyQualifiedTypeAliasConstructorTests {
    @Test func resolvesConstructorCallsThroughUnqualifiedJavaLangAliases() throws {
        let facade = """
        package java.lang
        public typealias Object = kotlin.Any
        """
        let consumer = """
        fun makeAny() = Any()
        fun makeObject() = Object()
        """
        try withTemporaryFiles(contents: [facade, consumer]) { inputs in
            let ctx = makeCompilationContext(
                inputs: inputs,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            _ = ctx.sourceManager.addFile(
                path: inputs[0],
                contents: Data(facade.utf8),
                origin: .bundledStdlib
            )
            _ = ctx.sourceManager.addFile(path: inputs[1], contents: Data(consumer.utf8))
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

            let ast = try #require(ctx.ast)
            let anyCall = try #require(firstExprID(in: ast, path: inputs[1], ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else {
                    return false
                }
                return ctx.interner.resolve(name) == "Any"
            })
            let objectCall = try #require(firstExprID(in: ast, path: inputs[1], ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else {
                    return false
                }
                return ctx.interner.resolve(name) == "Object"
            })
            let sema = try #require(ctx.sema)
            let anyBinding = try #require(sema.bindings.callBinding(for: anyCall))
            let objectBinding = try #require(sema.bindings.callBinding(for: objectCall))
            #expect(sema.symbols.symbol(objectBinding.chosenCallee)?.kind == .constructor)
            #expect(objectBinding.chosenCallee == anyBinding.chosenCallee)
            let owner = try #require(sema.symbols.parentSymbol(for: objectBinding.chosenCallee))
            #expect(sema.symbols.symbol(owner)?.fqName.map(ctx.interner.resolve) == ["kotlin", "Any"])
        }
    }

    @Test func resolvesConstructorCallsThroughQualifiedLibraryTypeAliases() throws {
        TestStdlibCache.shared.prepare()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: true)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        fun makeFailure() = java.io.IOException("failure")
        """.utf8))
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(
            named: "IOException", in: ast, path: path, ctx: ctx, interner: ctx.interner
        ).first)
        let sema = try #require(ctx.sema)
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
        let owner = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))
        #expect(sema.symbols.symbol(owner)?.fqName.map(ctx.interner.resolve) == ["kotlinx", "io", "IOException"])
    }

    @Test func resolvesGenericAndAnyConstructorsThroughQualifiedJavaTypeAliases() throws {
        TestStdlibCache.shared.prepare()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: true)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        fun main() {
            println(java.util.ArrayList<Int>())
            val value = java.lang.Object()
        }
        """.utf8))
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let arrayListCall = try #require(memberCallExprIDs(
            named: "ArrayList", in: ast, path: path, ctx: ctx, interner: ctx.interner
        ).first)
        let objectCall = try #require(memberCallExprIDs(
            named: "Object", in: ast, path: path, ctx: ctx, interner: ctx.interner
        ).first)
        for (call, expectedOwner) in [
            (arrayListCall, ["kotlin", "collections", "ArrayList"]),
            (objectCall, ["kotlin", "Any"]),
        ] {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
            let owner = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))
            #expect(sema.symbols.symbol(owner)?.fqName.map(ctx.interner.resolve) == expectedOwner)
        }
    }

    @Test func resolvesJavaUtilDateWithIntEpochLiteral() throws {
        let dateSource = """
        package java.util
        public class Date(
            internal val epochMilliseconds: Long,
        ) {
            public constructor() : this(0L)
            public fun getTime(): Long = epochMilliseconds
        }
        """
        let usageSource = """
        fun main() {
            val date = java.util.Date(0)
            val epoch: Long = date.getTime()
            java.util.Date()
        }
        """
        try withTemporaryFiles(contents: [dateSource, usageSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            // Keep the bundled Date constructor shape without compiling the full stdlib artifact.
            _ = ctx.sourceManager.addFile(
                path: paths[0], contents: Data(dateSource.utf8), origin: .bundledStdlib
            )
            _ = ctx.sourceManager.addFile(path: paths[1], contents: Data(usageSource.utf8))
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected Date(0) to resolve: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let dateCalls = memberCallExprIDs(
                named: "Date", in: ast, path: paths[1], ctx: ctx, interner: ctx.interner
            )
            let dateCall = try #require(dateCalls.first { call in
                guard case let .memberCall(_, _, _, arguments, _) = ast.arena.expr(call) else { return false }
                return arguments.count == 1
            })
            let defaultCall = try #require(dateCalls.first { call in
                guard case let .memberCall(_, _, _, arguments, _) = ast.arena.expr(call) else { return false }
                return arguments.isEmpty
            })
            guard case let .memberCall(_, _, _, arguments, _) = ast.arena.expr(dateCall) else {
                Issue.record("Expected java.util.Date(0) to be a member-call expression")
                return
            }
            let argument = try #require(arguments.first)
            let binding = try #require(sema.bindings.callBinding(for: dateCall))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            let owner = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))
            let defaultBinding = try #require(sema.bindings.callBinding(for: defaultCall))

            #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
            #expect(sema.symbols.symbol(owner)?.fqName.map(ctx.interner.resolve) == ["java", "util", "Date"])
            #expect(signature.parameterTypes == [sema.types.longType])
            #expect(sema.bindings.exprType(for: argument.expr) == sema.types.longType)
            #expect(sema.symbols.functionSignature(for: defaultBinding.chosenCallee)?.parameterTypes.isEmpty == true)
        }
    }
}
#endif
