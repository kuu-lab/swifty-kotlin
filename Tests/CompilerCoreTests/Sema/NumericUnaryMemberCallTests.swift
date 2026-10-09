@testable import CompilerCore
import Testing

@Suite
struct NumericUnaryMemberCallTests {
    @Test
    func namedUnarySignsInferNumericAndSafeCallResultTypes() throws {
        let types = ["Byte", "Short", "Int", "Long", "Float", "Double"]
        let source = types.enumerated().map { index, type in
            """
            fun sample\(index)(x: \(type), n: \(type)?) {
                x.unaryPlus()
                x.unaryMinus()
                n?.unaryPlus()
                n?.unaryMinus()
            }
            """
        }.joined(separator: "\n")
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var checkedCalls = 0
            for (index, expr) in ast.arena.exprs.enumerated() {
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.path(of: range.start.file) == path
                else { continue }
                let receiver: ExprID
                let safe: Bool
                switch expr {
                case let .memberCall(r, _, _, _, _):
                    receiver = r
                    safe = false
                case let .safeMemberCall(r, _, _, _, _):
                    receiver = r
                    safe = true
                default: continue
                }
                let receiverType = try #require(sema.bindings.exprType(for: receiver))
                let nonNull = sema.types.makeNonNullable(receiverType)
                let result = nonNull == sema.types.byteType || nonNull == sema.types.shortType
                    ? sema.types.intType : nonNull
                #expect(sema.bindings.exprType(for: id) == (safe ? sema.types.makeNullable(result) : result))
                #expect(sema.bindings.callBinding(for: id) != nil)
                checkedCalls += 1
            }
            #expect(checkedCalls == 24)
        }
    }

    @Test
    func namedUnarySignsRejectUnsupportedReceiversAndInvalidCalls() throws {
        let types = ["UInt", "ULong", "UByte", "UShort", "Char", "Boolean",
                     "List<Int>", "MutableList<Int>", "Set<Int>"]
        let sources = types.enumerated().map { index, type in
            """
            fun rejected\(index)(x: \(type)) {
                x.unaryPlus()
                x.unaryMinus()
            }
            """
        } + ["fun badNullable(x: Int?) { x.unaryPlus(); x.unaryMinus() }",
             "fun badArity(x: Int) { x.unaryPlus(1); x.unaryMinus(1) }"]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths.prefix(types.count) {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-0024" }.count == 2)
            }
            for path in paths.suffix(2) {
                #expect(diagnosticsForPath(path, in: ctx).contains { $0.severity == .error })
            }
        }
    }
}
