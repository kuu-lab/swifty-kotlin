#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CompanionCallableReferenceTests {
    @Test
    func classNameCompanionMemberReferenceBindsTheCompanionReceiver() throws {
        let source = """
        open class A {
            fun instance() = true
            companion object : A() {
                fun companion() = true
            }
        }
        fun call(f: () -> Boolean) = f()
        fun main() { call(A::companion) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "companion"
                else {
                    return nil
                }
                return exprID
            }.first)
            let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("A")]))
            let companion = try #require(sema.symbols.companionObjectSymbol(for: owner))
            let target = try #require(sema.bindings.identifierSymbol(for: reference))
            let referenceType = try #require(sema.bindings.exprType(for: reference))
            guard case let .functionType(function) = sema.types.kind(of: referenceType) else {
                Issue.record("Expected a callable reference function type.")
                return
            }

            #expect(sema.symbols.parentSymbol(for: target) == companion)
            #expect(function.receiver == nil)
            #expect(function.params.isEmpty)
            #expect(function.returnType == sema.types.booleanType)
            #expect(!sema.bindings.isUnboundCallableRef(reference))
        }
    }

    @Test
    func classNameCallableReferencePrefersExtensionOverCompanionMember() throws {
        // KUU-3674 (Kotlin 1.4 rule, JetBrains
        // callableReference/function/referenceToCompanionMember.kt): with no
        // constraining expected type, `B::foo` resolves to `fun B.foo()`
        // rather than the companion member `foo`.
        let source = """
        class A {
            companion object {
                fun foo(): String = "OK"
            }
        }
        class B {
            companion object {
                fun foo(): String = "Fail"
            }
        }
        fun B.foo(): String = "OK"
        fun call(f: Any) = f
        fun main() {
            call(A::foo)
            call(B::foo)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var aReference: ExprID?
            var bReference: ExprID?
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(receiver, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "foo",
                      let receiver,
                      case let .nameRef(receiverName, _) = ast.arena.expr(receiver)
                else {
                    continue
                }
                switch ctx.interner.resolve(receiverName) {
                case "A": aReference = exprID
                case "B": bReference = exprID
                default: break
                }
            }
            let aRef = try #require(aReference)
            let bRef = try #require(bReference)

            // A::foo still binds the companion member — no extension exists.
            let aOwner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("A")]))
            let aCompanion = try #require(sema.symbols.companionObjectSymbol(for: aOwner))
            let aTarget = try #require(sema.bindings.identifierSymbol(for: aRef))
            #expect(sema.symbols.parentSymbol(for: aTarget) == aCompanion)

            // B::foo binds the top-level extension `fun B.foo()`, not the
            // companion member, and keeps the unbound `(B) -> String` shape.
            let bOwner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("B")]))
            let bCompanion = try #require(sema.symbols.companionObjectSymbol(for: bOwner))
            let bTarget = try #require(sema.bindings.identifierSymbol(for: bRef))
            #expect(sema.symbols.parentSymbol(for: bTarget) != bCompanion)
            let bSymbol = try #require(sema.symbols.symbol(bTarget))
            #expect(bSymbol.fqName == [ctx.interner.intern("foo")])
            #expect(sema.bindings.isUnboundCallableRef(bRef))

            let referenceType = try #require(sema.bindings.exprType(for: bRef))
            guard case let .functionType(function) = sema.types.kind(of: referenceType) else {
                Issue.record("Expected a callable reference function type.")
                return
            }
            #expect(function.receiver == nil)
            #expect(function.params.count == 1)
            #expect(function.returnType == sema.types.stringType)
        }
    }

    @Test
    func classNameCallableReferenceExpectedTypeSelectsBetweenExtensionAndCompanion() throws {
        // KUU-3674: the extension is preferred only when it can satisfy the
        // expected type — `() -> String` still selects the bound companion
        // member because `(B) -> String` cannot fit it.
        let source = """
        class B {
            companion object {
                fun foo(): String = "Fail"
            }
        }
        fun B.foo(): String = "OK"
        val bound: () -> String = B::foo
        val unbound: (B) -> String = B::foo
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let bOwner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("B")]))
            let bCompanion = try #require(sema.symbols.companionObjectSymbol(for: bOwner))
            var sawBoundCompanion = false
            var sawUnboundExtension = false
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "foo",
                      let target = sema.bindings.identifierSymbol(for: exprID),
                      let referenceType = sema.bindings.exprType(for: exprID),
                      case let .functionType(function) = sema.types.kind(of: referenceType)
                else {
                    continue
                }
                if function.params.isEmpty {
                    sawBoundCompanion = true
                    #expect(sema.symbols.parentSymbol(for: target) == bCompanion)
                } else {
                    sawUnboundExtension = true
                    #expect(function.params.count == 1)
                    #expect(sema.symbols.parentSymbol(for: target) != bCompanion)
                    let targetSymbol = try #require(sema.symbols.symbol(target))
                    #expect(targetSymbol.fqName == [ctx.interner.intern("foo")])
                }
            }
            #expect(sawBoundCompanion)
            #expect(sawUnboundExtension)
        }
    }
}
#endif
