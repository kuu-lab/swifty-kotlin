#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite @MainActor
struct KIRModelsBehaviorTests {
    @Test func testArenaAppendLookupTransformAndModuleDerivedCounts() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let symA = symbols.define(
            kind: .function,
            name: interner.intern("alpha"),
            fqName: [interner.intern("pkg"), interner.intern("alpha")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let symB = symbols.define(
            kind: .function,
            name: interner.intern("beta"),
            fqName: [interner.intern("pkg"), interner.intern("beta")],
            declSite: nil,
            visibility: .public,
            flags: []
        )

        let arena = KIRArena()
        let expr0 = arena.appendExpr(.intLiteral(10), type: intType)
        let expr1 = arena.appendExpr(.boolLiteral(true))
        let expr2 = arena.appendExpr(.stringLiteral(interner.intern("hi")))
        let expr3 = arena.appendExpr(.symbolRef(symA))
        let expr4 = arena.appendExpr(.temporary(4))
        let expr5 = arena.appendExpr(.unit)
        let expr6 = arena.appendTemporary(type: intType)

        let fnA = KIRFunction(
            symbol: symA,
            name: interner.intern("alpha"),
            params: [KIRParameter(symbol: symA, type: types.anyType)],
            returnType: types.anyType,
            body: [
                .nop,
                .beginBlock,
                .label(100),
                .constValue(result: expr0, value: .intLiteral(10)),
                .constValue(result: expr1, value: .boolLiteral(true)),
                .constValue(result: expr2, value: .stringLiteral(interner.intern("txt"))),
                .constValue(result: expr3, value: .symbolRef(symB)),
                .constValue(result: expr4, value: .temporary(4)),
                .constValue(result: expr5, value: .unit),
                .binary(op: .add, lhs: expr0, rhs: expr0, result: expr4),
                .jumpIfEqual(lhs: expr0, rhs: expr1, target: 101),
                .jump(101),
                .label(101),
                .call(symbol: symB, callee: interner.intern("beta"), arguments: [expr0], result: expr4, canThrow: false, thrownResult: nil),
                .returnIfEqual(lhs: expr0, rhs: expr1),
                .returnValue(expr4),
                .endBlock,
            ],
            isSuspend: false,
            isInline: true
        )
        let fnB = KIRFunction(
            symbol: symB,
            name: interner.intern("beta"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let declFnA = arena.appendDecl(.function(fnA))
        _ = arena.appendDecl(.global(KIRGlobal(symbol: symA, type: types.anyType)))
        _ = arena.appendDecl(.nominalType(KIRNominalType(symbol: symB)))
        _ = arena.appendDecl(.function(fnB))

        #expect(arena.decl(declFnA) != nil)
        #expect(arena.decl(KIRDeclID(rawValue: -1)) == nil)
        #expect(arena.decl(KIRDeclID(rawValue: 999)) == nil)
        #expect(arena.expr(expr0) == .intLiteral(10))
        #expect(arena.exprType(expr0) == intType)
        #expect(expr6.rawValue == 6)
        #expect(arena.expr(expr6) == .temporary(6))
        #expect(arena.exprType(expr6) == intType)
        arena.setExprType(types.unitType, for: expr5)
        #expect(arena.exprType(expr5) == types.unitType)
        #expect(arena.expr(KIRExprID(rawValue: -1)) == nil)
        #expect(arena.expr(KIRExprID(rawValue: 999)) == nil)

        arena.transformFunctions { fn in
            var copy = fn
            copy.body.append(.nop)
            return copy
        }

        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declFnA])], arena: arena)
        #expect(module.functionCount == 2)
        #expect(module.symbolCount == 2)

        module.recordLowering("NormalizeBlocks")
        module.recordLowering("OperatorLowering")
        let dump = module.dump(interner: interner, symbols: symbols)

        #expect(dump.contains("function #\(symA.rawValue) alpha"))
        #expect(dump.contains("global"))
        #expect(dump.contains("type beta"))
        #expect(dump.contains("const r"))
        #expect(dump.contains("binary add"))
        #expect(dump.contains("label L100"))
        #expect(dump.contains("jumpIfEqual"))
        #expect(dump.contains("jump L101"))
        #expect(dump.contains("call beta"))
        #expect(dump.contains("returnIfEqual"))
        #expect(dump.contains("return r"))
        #expect(dump.contains("lowerings: NormalizeBlocks, OperatorLowering"))
    }
}
#endif
