@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct LocalOperatorDelegateTests {
    private func makeContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [false, true])
    func localOperatorIsSelectedOverOuterExtension(includeOuter: Bool) throws {
        let outer = includeOuter
            ? "operator fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 1"
            : ""
        let ctx = makeContext("""
        import kotlin.reflect.KProperty
        class ValueDelegate
        \(outer)
        fun main() {
            operator fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 2
            val answer by ValueDelegate()
            val result: Int = answer
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let localIndex = try #require(ast.arena.exprs.indices.first {
            if case .localFunDecl = ast.arena.exprs[$0] { return true }
            return false
        })
        let localID = ExprID(rawValue: Int32(localIndex))
        let local = try #require(sema.bindings.identifierSymbol(for: localID))
        #expect(ast.arena.isOperatorFunction(localID))
        #expect(sema.symbols.symbol(local)?.flags.contains(.operatorFunction) == true)
        let propertyIndex = try #require(ast.arena.exprs.indices.first {
            if case let .localDecl(name, _, _, _, isDelegated, _, _) = ast.arena.exprs[$0] {
                return isDelegated && name == ctx.interner.intern("answer")
            }
            return false
        })
        let propertyID = ExprID(rawValue: Int32(propertyIndex))
        let property = try #require(sema.bindings.identifierSymbol(for: propertyID))
        #expect(sema.symbols.delegateGetValueSymbol(for: property) == local)
    }

    @Test
    func nonOperatorIsAcceptedAsOrdinaryCall() throws {
        let ctx = makeContext("""
        import kotlin.reflect.KProperty
        class ValueDelegate
        fun probe(property: KProperty<*>) {
            fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 4
            val result: Int = ValueDelegate().getValue(null, property)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let localIndex = try #require(ast.arena.exprs.indices.first {
            if case .localFunDecl = ast.arena.exprs[$0] { return true }
            return false
        })
        let localID = ExprID(rawValue: Int32(localIndex))
        let local = try #require(sema.bindings.identifierSymbol(for: localID))
        #expect(!ast.arena.isOperatorFunction(localID))
        #expect(sema.symbols.symbol(local)?.flags.contains(.operatorFunction) == false)
        let callIndex = try #require(ast.arena.exprs.indices.first {
            if case let .memberCall(_, name, _, _, _) = ast.arena.exprs[$0] {
                return name == ctx.interner.intern("getValue")
            }
            return false
        })
        let call = ExprID(rawValue: Int32(callIndex))
        #expect(sema.bindings.identifierSymbol(for: call) == local)
        #expect(sema.bindings.exprType(for: call) == sema.types.intType)
    }

    @Test
    func nonOperatorIsRejectedAsDelegate() throws {
        let ctx = makeContext("""
        import kotlin.reflect.KProperty
        class ValueDelegate
        fun probe(property: KProperty<*>) {
            fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 4
            val result: Int = ValueDelegate().getValue(null, property)
            val answer by ValueDelegate()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0103")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let localIndex = try #require(ast.arena.exprs.indices.first {
            if case .localFunDecl = ast.arena.exprs[$0] { return true }
            return false
        })
        let localID = ExprID(rawValue: Int32(localIndex))
        let local = try #require(sema.bindings.identifierSymbol(for: localID))
        #expect(!ast.arena.isOperatorFunction(localID))
        #expect(sema.symbols.symbol(local)?.flags.contains(.operatorFunction) == false)
    }
}
