#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CallableReferenceNestedClassifierTests {
    @Test
    func genericInnerConstructorReferenceCapturesImplicitOuterReceiver() throws {
        let source = """
        public class Outer<OT>(val ot: OT) {
            inner class Inner<IT>(val it: IT, val ot2: OT)
            fun <II> createI(ii: II) = foo2(ii, ot, ::Inner)
        }
        fun <A, B, R> foo2(a: A, b: B, f: (A, B) -> R) = f(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "Inner"
                else {
                    return nil
                }
                return exprID
            }.first)
            let constructor = try #require(sema.bindings.identifierSymbol(for: reference))
            let innerClass = try #require(sema.symbols.parentSymbol(for: constructor))
            let outerClass = try #require(sema.symbols.parentSymbol(for: innerClass))
            let outerTypeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: outerClass).first)
            let binding = try #require(sema.bindings.callableReferenceBindings[reference])

            #expect(sema.symbols.symbol(constructor)?.kind == .constructor)
            #expect(sema.symbols.symbol(innerClass)?.flags.contains(.innerClass) == true)
            #expect(!sema.bindings.isUnboundCallableRef(reference))
            #expect(binding.substitutedTypeArguments.count == 2)
            guard case let .typeParam(capturedOuterParameter) = sema.types.kind(
                of: binding.substitutedTypeArguments[0]
            ) else {
                Issue.record("An implicitly bound inner constructor should capture the outer type parameter.")
                return
            }
            #expect(capturedOuterParameter.symbol == outerTypeParameter)
            guard case let .functionType(function) = sema.types.kind(
                of: try #require(sema.bindings.exprType(for: reference))
            ) else {
                Issue.record("An implicitly bound inner constructor reference should have a function type.")
                return
            }
            #expect(function.params.count == 2)
            guard case let .classType(resultType) = sema.types.kind(of: function.returnType) else {
                Issue.record("An inner constructor reference should return its inner class type.")
                return
            }
            #expect(resultType.classSymbol == innerClass)
        }
    }

    @Test
    func boundZeroArgumentInnerConstructorReferenceHasNoInputs() throws {
        try withTemporaryFile(contents: """
        class A { inner class I }
        fun make(): () -> A.I = A()::I
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "I"
                else {
                    return nil
                }
                return exprID
            }.first)
            let constructor = try #require(sema.bindings.identifierSymbol(for: reference))
            let innerClass = try #require(sema.symbols.parentSymbol(for: constructor))

            #expect(!sema.bindings.isUnboundCallableRef(reference))
            guard case let .functionType(function) = sema.types.kind(
                of: try #require(sema.bindings.exprType(for: reference))
            ) else {
                Issue.record("A bound inner constructor reference should have a function type.")
                return
            }
            #expect(function.receiver == nil)
            #expect(function.params.isEmpty)
            guard case let .classType(resultType) = sema.types.kind(of: function.returnType) else {
                Issue.record("A bound inner constructor reference should return its inner class type.")
                return
            }
            #expect(resultType.classSymbol == innerClass)
        }
    }

    @Test
    func boundInheritedInnerConstructorReferenceUsesOnlyConstructorInputs() throws {
        let source = """
        open class A(val prefix: String) {
            inner class I(val suffix: String)
        }
        class B(prefix: String) : A(prefix)
        fun make(): (String) -> A.I = B("outer")::I
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(member) == "I"
                else {
                    return nil
                }
                return exprID
            }.first)

            #expect(!sema.bindings.isUnboundCallableRef(reference))
            let constructor = try #require(sema.bindings.identifierSymbol(for: reference))
            #expect(sema.symbols.symbol(constructor)?.kind == .constructor)
            let innerClass = try #require(sema.symbols.parentSymbol(for: constructor))
            #expect(sema.symbols.symbol(innerClass)?.flags.contains(.innerClass) == true)

            let referenceType = try #require(sema.bindings.exprType(for: reference))
            guard case let .functionType(function) = sema.types.kind(of: referenceType) else {
                Issue.record("A bound inner constructor reference should have a function type.")
                return
            }
            #expect(function.receiver == nil)
            #expect(function.params == [sema.types.stringType])
            guard case let .classType(resultType) = sema.types.kind(of: function.returnType) else {
                Issue.record("A bound inner constructor reference should return its inner class type.")
                return
            }
            #expect(resultType.classSymbol == innerClass)
        }
    }

    @Test
    func unboundNestedClassifierMemberAndExtensionReferencesMatchExpectedTypes() throws {
        let source = """
        class A { class B { fun direct(): Boolean = true } }
        class Plain
        fun A.B.test(): Boolean = true
        fun Plain.test(): Boolean = true
        fun takeExtension(f: A.B.() -> Boolean): Boolean = f(A.B())
        fun takeFunction(f: (A.B) -> Boolean): Boolean = f(A.B())
        fun takePlain(f: (Plain) -> Boolean): Boolean = f(Plain())
        fun takeBound(f: () -> Boolean): Boolean = f()
        fun box(): Boolean = takeExtension(A.B::test) && takeFunction(A.B::test) && takeFunction(A.B::direct)
            && takePlain(Plain::test) && takeBound(A.B()::test)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let nestedClass = try #require(sema.symbols.lookup(
                fqName: ["A", "B"].map(ctx.interner.intern)
            ))
            let plainClass = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Plain")]))
            let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                      ["test", "direct"].contains(ctx.interner.resolve(member))
                else {
                    return nil
                }
                return exprID
            }
            try #require(references.count == 5)
            #expect(references.filter { sema.bindings.isUnboundCallableRef($0) }.count == 4)
            #expect(references.filter { !sema.bindings.isUnboundCallableRef($0) }.count == 1)

            for reference in references {
                let chosen = try #require(sema.bindings.identifierSymbol(for: reference))
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(signature.receiverType != nil)
                let isBoundControl = !sema.bindings.isUnboundCallableRef(reference)
                let type = try #require(sema.bindings.exprType(for: reference))
                guard case let .functionType(function) = sema.types.kind(of: type) else {
                    Issue.record("A callable reference should have a function type.")
                    continue
                }
                if isBoundControl {
                    #expect(function.receiver == nil)
                    #expect(function.params.isEmpty)
                    guard case let .callableRef(_, member, _) = ast.arena.expr(reference),
                          ctx.interner.resolve(member) == "test",
                          let signatureReceiver = signature.receiverType,
                          case let .classType(receiver) = sema.types.kind(of: signatureReceiver)
                    else {
                        Issue.record("The bound nested extension control should resolve to A.B.test.")
                        continue
                    }
                    #expect(receiver.classSymbol == nestedClass)
                    continue
                }
                let inputTypes = function.receiver.map { [$0] } ?? function.params
                #expect(inputTypes.count == 1)
                guard let receiverParameter = inputTypes.first,
                      case let .classType(receiver) = sema.types.kind(of: receiverParameter)
                else {
                    Issue.record("An unbound nested-class reference should take A.B as its first input.")
                    continue
                }
                let expectedClass: SymbolID
                guard let signatureReceiver = signature.receiverType,
                      case let .classType(declaredReceiver) = sema.types.kind(of: signatureReceiver)
                else {
                    Issue.record("The selected callable should declare a class receiver.")
                    continue
                }
                expectedClass = declaredReceiver.classSymbol
                #expect(receiver.classSymbol == expectedClass)
                #expect(expectedClass == nestedClass || expectedClass == plainClass)
            }
        }
    }
}
#endif
