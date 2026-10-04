#if canImport(Testing)
@testable import CompilerCore
import Testing

struct KIRVerifierTests {
    private func makeModule(
        arena: KIRArena,
        interner: StringInterner,
        body: [KIRInstruction]
    ) -> KIRModule {
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 9000),
            name: interner.intern("main"),
            params: [],
            returnType: TypeID(rawValue: 0),
            body: body,
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(function))
        return KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
    }

    @Test
    func testDuplicateLabelIsReported() {
        let interner = StringInterner()
        let arena = KIRArena()
        let module = makeModule(arena: arena, interner: interner, body: [
            .label(1),
            .label(1),
            .returnUnit,
        ])
        let failures = KIRVerifier.verify(module: module, symbols: nil, interner: interner)
        #expect(failures.contains { $0.kind == .duplicateLabel })
    }

    @Test
    func testUndefinedJumpTargetIsReported() {
        let interner = StringInterner()
        let arena = KIRArena()
        let module = makeModule(arena: arena, interner: interner, body: [
            .jump(77),
            .returnUnit,
        ])
        let failures = KIRVerifier.verify(module: module, symbols: nil, interner: interner)
        #expect(failures.contains { $0.kind == .undefinedJumpTarget })
    }

    @Test
    func testUndefinedRegisterReadIsReported() {
        let interner = StringInterner()
        let arena = KIRArena()
        let neverDefined = arena.appendExpr(.temporary(7), type: nil)
        let module = makeModule(arena: arena, interner: interner, body: [
            .returnValue(neverDefined),
        ])
        let failures = KIRVerifier.verify(module: module, symbols: nil, interner: interner)
        #expect(failures.contains { $0.kind == .undefinedRegisterRead })
    }

    @Test
    func testInstructionLocationCountMismatchIsReported() {
        let interner = StringInterner()
        let arena = KIRArena()
        var function = KIRFunction(
            symbol: SymbolID(rawValue: 9001),
            name: interner.intern("main"),
            params: [],
            returnType: TypeID(rawValue: 0),
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        function.instructionLocations = []
        let declID = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let failures = KIRVerifier.verify(module: module, symbols: nil, interner: interner)
        #expect(failures.contains { $0.kind == .instructionLocationCountMismatch })
    }

    @Test
    func testUnresolvableCalleeIsReported() {
        let interner = StringInterner()
        let arena = KIRArena()
        let module = makeModule(arena: arena, interner: interner, body: [
            .call(
                symbol: nil,
                callee: interner.intern("kk_definitely_not_a_runtime_function"),
                arguments: [],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ),
            .returnUnit,
        ])
        let failures = KIRVerifier.verify(module: module, symbols: nil, interner: interner)
        #expect(failures.contains { $0.kind == .unresolvableCallee })
    }

    @Test
    func testSyntheticAccessorAndDefaultStubCalleesAreResolvable() {
        let interner = StringInterner()
        let arena = KIRArena()
        let receiver = arena.appendExpr(.temporary(0), type: nil)
        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(
            for: SymbolID(rawValue: 42)
        )
        let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(
            for: SymbolID(rawValue: 43)
        )
        let module = makeModule(arena: arena, interner: interner, body: [
            .constValue(result: receiver, value: .intLiteral(0)),
            .call(
                symbol: getterSymbol,
                callee: interner.intern("get"),
                arguments: [receiver],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ),
            .call(
                symbol: stubSymbol,
                callee: interner.intern("indexOf$default"),
                arguments: [],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ),
            .returnUnit,
        ])
        let failures = KIRVerifier.verify(module: module, symbols: nil, interner: interner)
        #expect(failures.isEmpty, "unexpected failures: \(failures)")
    }

    @Test
    func testWellFormedFunctionProducesNoFailures() {
        let interner = StringInterner()
        let arena = KIRArena()
        let value = arena.appendExpr(.temporary(0), type: nil)
        let result = arena.appendExpr(.temporary(1), type: nil)
        let module = makeModule(arena: arena, interner: interner, body: [
            .constValue(result: value, value: .intLiteral(1)),
            .call(
                symbol: nil,
                callee: interner.intern("kk_unbox_int"),
                arguments: [value],
                result: result,
                canThrow: false,
                thrownResult: nil
            ),
            .returnValue(result),
        ])
        let failures = KIRVerifier.verify(module: module, symbols: nil, interner: interner)
        #expect(failures.isEmpty, "unexpected failures: \(failures)")
    }

    @Test
    func testLoweringPhaseEmitsNoVerifierDiagnosticsForHelloWorld() throws {
        let source = """
        fun main() {
            println("hello")
        }
        """
        let ctx = makeContextFromSource(source, moduleName: "KIRVerifierSmoke")
        try runToLowering(ctx)
        let kirDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-KIR-0003"
        }
        #expect(kirDiagnostics.isEmpty, "unexpected KIR verifier failures: \(kirDiagnostics)")
        #expect(!ctx.diagnostics.hasError)
    }
}
#endif
