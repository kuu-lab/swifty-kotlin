#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ASTModelsTestsPart2 {
    @Test
    func testConstructorDeclAndDelegationCallInitializers() {
        let interner = StringInterner()
        let range = makeRange(start: 10, end: 50)
        let typeRef = TypeRefID(rawValue: 0)

        let delegationThis = ConstructorDelegationCall(
            kind: .this,
            args: [CallArgument(label: nil, expr: ExprID(rawValue: 0))],
            range: range
        )
        #expect(delegationThis.kind == .this)
        #expect(delegationThis.args.count == 1)
        #expect(delegationThis.range == range)

        let delegationSuper = ConstructorDelegationCall(
            kind: .super_,
            args: [],
            range: range
        )
        #expect(delegationSuper.kind == .super_)
        #expect(delegationSuper.args.isEmpty)
        #expect(delegationThis != delegationSuper)

        let ctorDefault = ConstructorDecl(range: range)
        #expect(ctorDefault.range == range)
        #expect(ctorDefault.modifiers == [])
        #expect(ctorDefault.valueParams.isEmpty)
        #expect(ctorDefault.delegationCall == nil)
        #expect(ctorDefault.body == .unit)

        let param = ValueParamDecl(name: interner.intern("x"), type: typeRef)
        let ctorFull = ConstructorDecl(
            range: range,
            modifiers: [.public],
            valueParams: [param],
            delegationCall: delegationThis,
            body: .block([ExprID(rawValue: 1)], range)
        )
        #expect(ctorFull.modifiers == [.public])
        #expect(ctorFull.valueParams.count == 1)
        #expect(ctorFull.delegationCall != nil)
        if case let .block(exprs, _) = ctorFull.body {
            #expect(exprs.count == 1)
        } else {
            Issue.record("Expected .block body")
        }

        let classDeclWithCtor = ClassDecl(
            range: range,
            name: interner.intern("Foo"),
            modifiers: [],
            typeParams: [],
            primaryConstructorParams: [],
            secondaryConstructors: [ctorFull]
        )
        #expect(classDeclWithCtor.secondaryConstructors.count == 1)
        #expect(classDeclWithCtor.initBlocks.isEmpty)
    }
}
#endif
