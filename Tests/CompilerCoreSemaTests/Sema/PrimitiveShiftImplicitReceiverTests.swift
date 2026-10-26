@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrimitiveShiftImplicitReceiverTests {

    @Test
    func testIntAndLongShiftCallsResolveOnImplicitReceivers() throws {
        let source = """
        package shifts

        infix fun Int.intShifts(bits: Int): Int = shl(bits) + shr(bits) + ushr(bits)
        infix fun Long.longShifts(bits: Int): Long = shl(bits) + shr(bits) + ushr(bits)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(diagnostics.isEmpty, "Unexpected diagnostics: \(diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let shiftNames: Set<String> = ["shl", "shr", "ushr"]
            var checkedCalls = 0
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard case let .call(callee, _, _, range) = ast.arena.expr(id),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      shiftNames.contains(ctx.interner.resolve(name))
                else {
                    continue
                }

                let binding = try #require(sema.bindings.callBindings[id])
                let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
                let receiverType = try #require(signature.receiverType)
                let resultType = try #require(sema.bindings.exprType(for: id))
                #expect(receiverType == sema.types.intType || receiverType == sema.types.longType)
                #expect(resultType == receiverType)
                checkedCalls += 1
            }
            #expect(checkedCalls == 6)
        }
    }
}
