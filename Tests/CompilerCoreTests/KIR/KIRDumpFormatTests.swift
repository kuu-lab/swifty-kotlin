#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Pins `KIRModule.dump` byte-for-byte across every instruction and constant
/// shape, so renderer optimizations can be checked against the format the
/// reflection-based implementation produced.
@Suite
struct KIRDumpFormatTests {
    static func makeModule() -> (KIRModule, StringInterner, SymbolTable) {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let callee = symbols.define(
            kind: .function, name: interner.intern("callee"),
            fqName: [interner.intern("pkg"), interner.intern("callee")],
            declSite: nil, visibility: .public, flags: []
        )
        let owner = symbols.define(
            kind: .class, name: interner.intern("Owner"),
            fqName: [interner.intern("pkg"), interner.intern("Owner")],
            declSite: nil, visibility: .public, flags: []
        )
        let arena = KIRArena()
        let r: [KIRExprID] = (0 ..< 4).map { _ in arena.appendTemporary(type: types.anyType) }
        let constants: [KIRExprKind] = [
            .intLiteral(-7), .longLiteral(Int64.max), .uintLiteral(UInt64.max), .ulongLiteral(3),
            .floatLiteral(1.5), .doubleLiteral(-0.0), .doubleLiteral(.infinity), .doubleLiteral(.nan),
            .doubleLiteral(0.1), .doubleLiteral(1e300), .charLiteral(65), .boolLiteral(false),
            .stringLiteral(interner.intern("a\"b")), .symbolRef(callee), .symbolRef(SymbolID(rawValue: -42)),
            .externSymbolAddress(interner.intern("kk_extern")), .temporary(9), .null, .unit,
        ]
        let binaryOps: [KIRBinaryOp] = [
            .add, .subtract, .multiply, .divide, .modulo, .equal, .notEqual, .lessThan,
            .lessOrEqual, .greaterThan, .greaterOrEqual, .logicalAnd, .logicalOr,
        ]
        let unaryOps: [KIRUnaryOp] = [.not, .unaryPlus, .unaryMinus]
        var body: [KIRInstruction] = [.nop, .beginBlock, .label(1), .jump(2), .jumpIfEqual(lhs: r[0], rhs: r[1], target: 3)]
        body += constants.map { .constValue(result: r[0], value: $0) }
        body += binaryOps.map { .binary(op: $0, lhs: r[0], rhs: r[1], result: r[2]) }
        body += unaryOps.map { .unary(op: $0, operand: r[0], result: r[1]) }
        body += [
            .nullAssert(operand: r[0], result: r[1]),
            .call(symbol: nil, callee: interner.intern("kk_plain"), arguments: [], result: nil, canThrow: false),
            .call(
                symbol: callee, callee: interner.intern("callee"), arguments: [r[0], r[1]], result: r[2],
                canThrow: true, thrownResult: r[3], isSuperCall: true, qualifiedSuperType: owner
            ),
            .virtualCall(
                symbol: callee, callee: interner.intern("v"), receiver: r[0], arguments: [r[1]],
                result: r[2], canThrow: false, dispatch: .vtable(slot: 4)
            ),
            .virtualCall(
                symbol: nil, callee: interner.intern("i"), receiver: r[0], arguments: [], result: nil,
                canThrow: true, thrownResult: r[3], dispatch: .itable(interfaceSlot: 1, methodSlot: 2)
            ),
            .virtualCall(
                callee: interner.intern("d"), receiver: r[0], arguments: [r[1], r[2]], result: r[3],
                canThrow: false, dispatch: .itableDynamic(interfaceTypeID: -5, methodSlot: 6)
            ),
            .jumpIfNotNull(value: r[0], target: 7),
            .copy(from: r[0], to: r[1]),
            .storeGlobal(value: r[0], symbol: owner),
            .loadGlobal(result: r[1], symbol: owner),
            .rethrow(value: r[2]),
            .returnIfEqual(lhs: r[0], rhs: r[1]),
            .nonLocalReturn(r[0], target: .function(callee)),
            .nonLocalReturn(nil, target: .importedFunction(interner.intern("imported"))),
            .nonLocalReturn(r[1]),
            .nonLocalReturn(nil),
            .beginFinallyGuard,
            .beginNonLocalReturnScope(value: r[0], target: 8, function: .function(callee)),
            .beginNonLocalReturnScope(value: r[1], target: 9),
            .endNonLocalReturnScope,
            .resumeNonLocalReturn(r[2]),
            .beginFinallyCleanup(skipping: 2),
            .endFinallyCleanup,
            .endFinallyGuard,
            .endBlock,
            .returnValue(r[3]),
            .returnUnit,
        ]
        _ = arena.appendDecl(.function(KIRFunction(
            symbol: callee, name: interner.intern("callee"), params: [KIRParameter(symbol: callee, type: types.anyType)],
            returnType: types.anyType, body: body, isSuspend: true, isInline: false
        )))
        _ = arena.appendDecl(.global(KIRGlobal(symbol: owner, type: types.anyType)))
        _ = arena.appendDecl(.nominalType(KIRNominalType(symbol: owner)))
        _ = arena.appendDecl(.nominalType(KIRNominalType(symbol: SymbolID(rawValue: 999))))
        let module = KIRModule(files: [], arena: arena)
        module.recordLowering("NormalizeBlocks")
        module.recordLowering("ABILowering")
        return (module, interner, symbols)
    }

    @Test
    func testDumpFormatIsStable() {
        let (module, interner, symbols) = Self.makeModule()
        let dump = module.dump(interner: interner, symbols: symbols)
        #expect(dump == Self.expected)
    }

    static let expected = #"""
    decl[0] function #0 callee params=1 suspend=true inline=false
      nop
      beginBlock
      label L1
      jump L2
      jumpIfEqual r0, r1 -> L3
      const r0=intLiteral(-7)
      const r0=longLiteral(9223372036854775807)
      const r0=uintLiteral(18446744073709551615)
      const r0=ulongLiteral(3)
      const r0=floatLiteral(1.5)
      const r0=doubleLiteral(-0.0)
      const r0=doubleLiteral(inf)
      const r0=doubleLiteral(nan)
      const r0=doubleLiteral(0.1)
      const r0=doubleLiteral(1e+300)
      const r0=charLiteral(65)
      const r0=boolLiteral(false)
      const r0=stringLiteral("a"b")
      const r0=symbolRef(CompilerCore.SymbolID(rawValue: 0))
      const r0=symbolRef(CompilerCore.SymbolID(rawValue: -42))
      const r0=externSymbolAddress("kk_extern")
      const r0=temporary(9)
      const r0=null
      const r0=unit
      binary add r0, r1 -> r2
      binary subtract r0, r1 -> r2
      binary multiply r0, r1 -> r2
      binary divide r0, r1 -> r2
      binary modulo r0, r1 -> r2
      binary equal r0, r1 -> r2
      binary notEqual r0, r1 -> r2
      binary lessThan r0, r1 -> r2
      binary lessOrEqual r0, r1 -> r2
      binary greaterThan r0, r1 -> r2
      binary greaterOrEqual r0, r1 -> r2
      binary logicalAnd r0, r1 -> r2
      binary logicalOr r0, r1 -> r2
      unary not r0 -> r1
      unary unaryPlus r0 -> r1
      unary unaryMinus r0 -> r1
      nullAssert r0 -> r1
      call kk_plain symbol=_ args=[] ret=_ thrown=false thrownResult=_
      call callee symbol=callee args=[r0, r1] ret=r2 thrown=true thrownResult=r3 super=1 qualifiedSuper=1
      virtualCall v symbol=callee receiver=r0 args=[r1] ret=r2 thrown=false thrownResult=_ dispatch=vtable[4]
      virtualCall i symbol=_ receiver=r0 args=[] ret=_ thrown=true thrownResult=r3 dispatch=itable[1:2]
      virtualCall d symbol=_ receiver=r0 args=[r1, r2] ret=r3 thrown=false thrownResult=_ dispatch=itableDynamic[-5:6]
      jumpIfNotNull r0 -> L7
      copy r0 -> r1
      storeGlobal r0 -> s1
      loadGlobal s1 -> r1
      rethrow r2
      returnIfEqual r0, r1
      nonLocalReturn r0 target=function(CompilerCore.SymbolID(rawValue: 0))
      nonLocalReturnUnit target=importedFunction(CompilerCore.InternedString(rawValue: 9))
      nonLocalReturn r1
      nonLocalReturnUnit
      beginFinallyGuard
      beginNonLocalReturnScope r0, L8 function=function(CompilerCore.SymbolID(rawValue: 0))
      beginNonLocalReturnScope r1, L9
      endNonLocalReturnScope
      resumeNonLocalReturn r2
      beginFinallyCleanup skipping=2
      endFinallyCleanup
      endFinallyGuard
      endBlock
      return r3
      returnUnit
    decl[1] global
    decl[2] type Owner
    decl[3] type
    lowerings: NormalizeBlocks, ABILowering
    """#
}
#endif
