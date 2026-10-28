#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct TypeNameCompanionInvokeResolutionTests {
    private func context(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    private func expectSelectedCall(
        source: String,
        kind: SymbolKind,
        owner: [String],
        callName: String = "Box"
    ) throws -> (CompilationContext, ExprID) {
        let ctx = context(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .call(calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID),
                  case let .nameRef(calleeName, _) = calleeExpr
            else {
                return nil
            }
            return ctx.interner.resolve(calleeName) == callName ? exprID : nil
        }
        let call = try #require(calls.last)
        let binding = try #require(sema.bindings.callBinding(for: call))
        let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
        let chosenOwner = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))

        #expect(chosen.kind == kind)
        #expect(sema.symbols.symbol(chosenOwner)?.fqName.map(ctx.interner.resolve) == owner)
        return (ctx, call)
    }

    @Test func genericInterfaceTypeNameCallUsesCompanionInvoke() throws {
        let (ctx, call) = try expectSelectedCall(source: """
        interface Box<T> {
            val value: T
            companion object {
                operator fun <T> invoke(value: T): Box<T> = Impl(value)
            }
        }
        class Payload
        class Impl<T>(override val value: T) : Box<T>
        fun make(): Box<Payload> = Box(Payload())
        """, kind: .function, owner: ["Box", "Companion"])

        let sema = try #require(ctx.sema)
        let boxSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Box")]))
        let payloadSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Payload")]))
        let payloadType = sema.types.make(.classType(ClassType(
            classSymbol: payloadSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedType = sema.types.make(.classType(ClassType(
            classSymbol: boxSymbol,
            args: [.invariant(payloadType)],
            nullability: .nonNull
        )))
        #expect(sema.bindings.exprType(for: call) == expectedType)
        #expect(sema.bindings.isInvokeOperatorCall(call))
    }

    @Test func classNameCallFallsBackWhenConstructorIsInapplicable() throws {
        _ = try expectSelectedCall(source: """
        class Number
        class Text
        class Box(val value: Number) {
            companion object { operator fun invoke(value: Text): Box = Box(Number()) }
        }
        fun make(): Box = Box(Text())
        """, kind: .function, owner: ["Box", "Companion"])
    }

    @Test func applicableConstructorHasPriorityOverCompanionInvoke() throws {
        let (ctx, call) = try expectSelectedCall(source: """
        class Payload
        class Box(val value: Payload) {
            companion object { operator fun invoke(value: Payload): Box = Box(value) }
        }
        fun make(): Box = Box(Payload())
        """, kind: .constructor, owner: ["Box"])

        let sema = try #require(ctx.sema)
        #expect(!sema.bindings.isInvokeOperatorCall(call))
    }

    @Test func privateConstructorDoesNotHideCompanionInvoke() throws {
        _ = try expectSelectedCall(source: """
        class Payload
        class Box private constructor(val value: Payload) {
            companion object { operator fun invoke(value: Payload): Box = Box(value) }
        }
        fun make(): Box = Box(Payload())
        """, kind: .function, owner: ["Box", "Companion"])
    }

    @Test func ambiguousCompanionInvokeOverloadsStayAmbiguous() throws {
        let ctx = context("""
        interface Left
        interface Right
        class Both : Left, Right
        class Product
        interface Box {
            companion object {
                operator fun invoke(value: Left): Product = Product()
                operator fun invoke(value: Right): Product = Product()
            }
        }
        fun make(): Product = Box(Both())
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1, "Expected overload ambiguity: \(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0023" }, "Expected invoke candidates, got: \(errors)")
    }
}
#endif
