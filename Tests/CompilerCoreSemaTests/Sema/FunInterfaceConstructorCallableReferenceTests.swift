#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct FunInterfaceConstructorCallableReferenceTests {
    private func context(_ source: String) throws -> CompilationContext {
        let path = "/fun-interface-constructor-reference.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test
    func funInterfaceConstructorReferenceHasSyntheticSamFactoryType() throws {
        let ctx = try context("""
        fun interface KRunnable { fun run() }
        val kr = ::KRunnable
        fun main() {
            val ctor: (() -> Unit) -> KRunnable = ::KRunnable
        }
        """)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let file = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[0]))
        let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let expression = ExprID(rawValue: Int32(index))
            guard ast.arena.exprRange(expression)?.start.file == file,
                  case .callableRef? = ast.arena.expr(expression)
            else { return nil }
            return expression
        }
        try #require(references.count == 2)
        for reference in references {
            let type = try #require(sema.bindings.exprType(for: reference))
            guard case let .functionType(function) = sema.types.kind(of: type) else {
                Issue.record("A fun-interface constructor reference should have a function type.")
                continue
            }
            #expect(function.isCallableReference)
            #expect(function.params.count == 1)
            guard let parameter = function.params.first,
                  case let .functionType(samFunction) = sema.types.kind(of: parameter)
            else {
                Issue.record("The constructor reference should accept its SAM function value.")
                continue
            }
            #expect(samFunction.params.isEmpty)
            #expect(samFunction.returnType == sema.types.unitType)
            guard case let .classType(interfaceType) = sema.types.kind(of: function.returnType),
                  let interface = sema.symbols.symbol(interfaceType.classSymbol)
            else {
                Issue.record("The constructor reference should return KRunnable.")
                continue
            }
            #expect(ctx.interner.resolve(interface.name) == "KRunnable")
            #expect(interface.flags.contains(.funInterface))
            #expect(sema.bindings.callableRefKind(for: reference) == .functionRef)
            #expect(!sema.bindings.isSamConversion(reference))
            #expect(sema.bindings.samInterfaceType(for: reference) == function.returnType)
            #expect(sema.bindings.samUnderlyingFunctionType(for: reference) == parameter)
        }
    }

    @Test
    func ordinaryInterfaceDoesNotGainAConstructorReference() throws {
        let ctx = try context("""
        interface Ordinary { fun run() }
        fun invalid(): (() -> Unit) -> Ordinary = ::Ordinary
        """)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0022"
        })
    }
}
#endif
