#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CallableReferenceNestedClassifierTests {
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
