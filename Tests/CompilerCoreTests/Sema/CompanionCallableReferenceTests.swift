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

    @Test
    func classNameCallableReferenceBindsInheritingCompanionReceiver() throws {
        // KUU-3683 (JetBrains
        // callableReference/bound/companionObjectReceiverInheritsFromOuter.kt):
        // `A::member` where `companion object : A()` also carries a bound
        // interpretation on the `A.Companion` singleton. An expected
        // `() -> Boolean` selects it for members and extensions of `A`, and
        // unconditionally for members/extensions declared on `A.Companion`.
        let source = """
        open class A {
            fun instance() = true
            companion object : A() {
                fun companion() = true
            }
        }
        fun A.ext() = true
        fun A.Companion.companionExt() = true
        fun call(f: () -> Boolean) = f()
        fun main() {
            call(A::instance)
            call(A::ext)
            call(A::companionExt)
            call(A::companion)
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
            var boundMembers = Set<String>()
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      let referenceType = sema.bindings.exprType(for: exprID),
                      case let .functionType(function) = sema.types.kind(of: referenceType)
                else {
                    continue
                }
                let name = ctx.interner.resolve(member)
                // Every reference is bound: it has no leading receiver
                // parameter and it is not marked as an unbound reference.
                #expect(!sema.bindings.isUnboundCallableRef(exprID), "A::\(name) should be bound")
                #expect(function.params.isEmpty, "A::\(name) should have no value parameters")
                #expect(function.returnType == sema.types.booleanType)
                boundMembers.insert(name)
            }
            #expect(boundMembers == ["instance", "ext", "companionExt", "companion"])
        }
    }

    @Test
    func classNameCallableReferenceBindsInheritingCompanionReceiverForProperties() throws {
        // KUU-3683: the same bound interpretation applies to property
        // references — `A::instanceProp` / `A::extProp` bind the companion
        // only when it inherits `A`, while `A::companionExtProp` (declared on
        // `A.Companion`) binds it unconditionally.
        let source = """
        open class A {
            val instanceProp = true
            companion object : A() {
                val companionProp = true
            }
        }
        val A.extProp get() = true
        val A.Companion.companionExtProp get() = true
        fun call(f: () -> Boolean) = f()
        fun main() {
            call(A::instanceProp)
            call(A::extProp)
            call(A::companionExtProp)
            call(A::companionProp)
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
            var boundMembers = Set<String>()
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID)
                else {
                    continue
                }
                let name = ctx.interner.resolve(member)
                #expect(!sema.bindings.isUnboundCallableRef(exprID), "A::\(name) should be bound")
                #expect(sema.bindings.callableRefKind(for: exprID) == .propertyRef)
                boundMembers.insert(name)
            }
            #expect(boundMembers == ["instanceProp", "extProp", "companionExtProp", "companionProp"])
        }
    }

    @Test
    func classNameCallableReferenceKeepsUnboundShapeWhenExpectedAcceptsIt() throws {
        // KUU-3683: the bound companion interpretation must not steal the
        // ordinary unbound reference — `(A) -> Boolean` keeps `A::instance`
        // unbound even when the companion inherits `A`.
        let source = """
        open class A {
            fun instance() = true
            companion object : A() {
                fun companion() = true
            }
        }
        val unbound: (A) -> Boolean = A::instance
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
            let reference = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "instance"
                else {
                    return nil
                }
                return exprID
            }.first)
            #expect(sema.bindings.isUnboundCallableRef(reference))
            let referenceType = try #require(sema.bindings.exprType(for: reference))
            guard case let .functionType(function) = sema.types.kind(of: referenceType) else {
                Issue.record("Expected a callable reference function type.")
                return
            }
            #expect(function.params.count == 1)
        }
    }

    @Test
    func classNameCallableReferenceRejectsCompanionThatDoesNotInherit() throws {
        // KUU-3683: when the companion object does NOT inherit `A`, members
        // and extensions of `A` cannot bind the companion receiver —
        // `B::instance` for `() -> Boolean` must stay an error, matching
        // kotlinc's "inapplicable candidate". Extensions on `B.Companion`
        // itself still bind the singleton unconditionally.
        let source = """
        open class B {
            fun instance() = true
            val instanceProp = true
            companion object {
                fun companion() = true
            }
        }
        fun B.ext() = true
        fun B.Companion.companionExt() = true
        fun call(f: () -> Boolean) = f()
        fun main() {
            call(B::instance)
            call(B::ext)
            call(B::instanceProp)
            call(B::companionExt)
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
            #expect(errors.count == 3, "Expected 3 diagnostics, got: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            // `B::companionExt` still resolves: its declared receiver is
            // `B.Companion` itself, which the singleton always satisfies.
            let companionExtRef = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "companionExt"
                else {
                    return nil
                }
                return exprID
            }.first)
            #expect(!sema.bindings.isUnboundCallableRef(companionExtRef))
            let referenceType = try #require(sema.bindings.exprType(for: companionExtRef))
            guard case let .functionType(function) = sema.types.kind(of: referenceType) else {
                Issue.record("Expected a callable reference function type.")
                return
            }
            #expect(function.params.isEmpty)
        }
    }
}
#endif
