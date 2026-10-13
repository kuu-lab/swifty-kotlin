#if canImport(Testing)
@testable import CompilerCore
import Testing

extension LoweringPassRegressionTests {
    @Test
    func ownedNonLocalReturnStopsBeforeCallerCleanup() {
        let arena = KIRArena()
        let types = TypeSystem()
        let function = SymbolID(rawValue: 200)
        let value = arena.appendExpr(.intLiteral(42), type: types.intType)
        let result = arena.appendTemporary(type: types.intType)
        let callerCleanup = arena.appendTemporary()
        let cleanup = arena.appendTemporary()
        let body: [KIRInstruction] = [
            .beginNonLocalReturnScope(value: callerCleanup, target: 10),
            .beginNonLocalReturnScope(value: result, target: 20, function: .function(function)),
            .beginNonLocalReturnScope(value: cleanup, target: 30),
            .nonLocalReturn(value, target: .function(function)),
            .endNonLocalReturnScope, .label(30), .resumeNonLocalReturn(cleanup),
            .endNonLocalReturnScope, .label(20),
            .endNonLocalReturnScope, .label(10), .resumeNonLocalReturn(callerCleanup),
            .returnUnit,
        ]
        let lowered = InlineLoweringPass().resolveNonLocalReturnScopes(
            body, locations: [], arena: arena, unitType: types.unitType, returnType: types.unitType
        )
        #expect(lowered.body == [
            .copy(from: value, to: cleanup), .jump(30), .label(30),
            .copy(from: cleanup, to: result), .jump(20), .label(20), .label(10), .returnUnit,
        ])
        #expect(arena.exprType(cleanup) == types.intType)
    }

    @Test
    func nonLocalReturnScopesRouteInnermostCleanupThenOuterCleanup() {
        let arena = KIRArena()
        let types = TypeSystem()
        let value = arena.appendExpr(.intLiteral(31), type: types.intType)
        let inner = arena.appendTemporary()
        let outer = arena.appendTemporary()
        let body: [KIRInstruction] = [
            .beginNonLocalReturnScope(value: outer, target: 10),
            .beginNonLocalReturnScope(value: inner, target: 20),
            .nonLocalReturn(value),
            .endNonLocalReturnScope,
            .label(20),
            .resumeNonLocalReturn(inner),
            .endNonLocalReturnScope,
            .label(10),
            .resumeNonLocalReturn(outer),
        ]
        let lowered = InlineLoweringPass().resolveNonLocalReturnScopes(
            body, locations: Array(repeating: nil, count: body.count),
            arena: arena, unitType: types.unitType
        )
        #expect(lowered.body == [
            .copy(from: value, to: inner), .jump(20), .label(20),
            .copy(from: inner, to: outer), .jump(10), .label(10), .returnValue(outer),
        ])
        #expect(lowered.locations.count == lowered.body.count)
    }

    @Test
    func inlineNonLocalReturnRunsCallerFinallyThroughContinuation() throws {
        let context = makeContextFromSource("""
        inline fun once(block: () -> Unit) { block() }
        fun escape(): Int {
            try { once { return 31 } } finally { println("outer-finally") }
            return -1
        }
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let module = try #require(context.kir)
        let escape = try #require(module.arena.declarations.compactMap { declaration -> KIRFunction? in
            if case let .function(function) = declaration { return function }
            return nil
        }.first {
            $0.name == context.interner.intern("escape")
        })
        #expect(extractCallees(from: escape.body, interner: context.interner).contains("println"))
        #expect(!escape.body.contains { instruction in
            switch instruction {
            case .nonLocalReturn, .beginNonLocalReturnScope, .endNonLocalReturnScope, .resumeNonLocalReturn,
                 .beginFinallyCleanup, .endFinallyCleanup:
                return true
            default: return false
            }
        })
        #expect(escape.body.contains { if case .jump = $0 { return true }; return false })
    }

    @Test
    func nonLocalReturnFromEagerCleanupSkipsItsOwnFinally() {
        let arena = KIRArena()
        let types = TypeSystem()
        let value = arena.appendExpr(.intLiteral(31), type: types.intType)
        let inner = arena.appendTemporary()
        let outer = arena.appendTemporary()
        let body: [KIRInstruction] = [
            .beginNonLocalReturnScope(value: outer, target: 10),
            .beginNonLocalReturnScope(value: inner, target: 20),
            .beginFinallyCleanup(skipping: 1), .nonLocalReturn(value), .endFinallyCleanup,
            .endNonLocalReturnScope, .label(20), .resumeNonLocalReturn(inner),
            .endNonLocalReturnScope, .label(10), .resumeNonLocalReturn(outer),
        ]
        let lowered = InlineLoweringPass().resolveNonLocalReturnScopes(
            body, locations: [], arena: arena, unitType: types.unitType
        )
        #expect(lowered.body == [
            .copy(from: value, to: outer), .jump(10), .label(20), .label(10), .returnValue(outer),
        ])
        #expect(arena.exprType(outer) == types.intType)
    }

    @Test
    func cleanupSlotUsesCallerReturnTypeAndUnusedContinuationsDisappear() {
        let arena = KIRArena()
        let types = TypeSystem()
        let value = arena.appendExpr(.doubleLiteral(1.25), type: types.doubleType)
        let slot = arena.appendTemporary()
        let body: [KIRInstruction] = [
            .beginNonLocalReturnScope(value: slot, target: 10), .nonLocalReturn(value),
            .endNonLocalReturnScope, .label(10), .resumeNonLocalReturn(slot),
        ]
        let lowered = InlineLoweringPass().resolveNonLocalReturnScopes(
            body, locations: [], arena: arena, unitType: types.unitType, returnType: types.doubleType
        )
        #expect(arena.exprType(slot) == types.doubleType)
        #expect(lowered.body.last == .returnValue(slot))
        let unused = InlineLoweringPass().resolveNonLocalReturnScopes(
            body.filter { if case .nonLocalReturn = $0 { return false }; return true },
            locations: [], arena: arena, unitType: types.unitType, returnType: types.doubleType
        )
        #expect(unused.body == [.label(10)])
    }

    @Test
    func finallyScopesAreResolvedWithoutAnyInlineFunctions() throws {
        let context = makeContextFromSource("""
        fun escape(): Int {
            try { return 31 } finally { println("ordinary-finally") }
        }
        """)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        #expect(context.kir?.arena.declarations.allSatisfy { declaration in
            guard case let .function(function) = declaration else { return true }
            return !function.body.contains { instruction in
                switch instruction {
                case .beginNonLocalReturnScope, .endNonLocalReturnScope, .resumeNonLocalReturn,
                     .beginFinallyCleanup, .endFinallyCleanup: return true
                default: return false
                }
            }
        } == true)
    }
}
#endif
