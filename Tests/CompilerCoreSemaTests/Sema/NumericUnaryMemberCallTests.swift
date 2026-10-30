@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
            let cases: [(type: String, expectedDirect: TypeID, expectedSafe: TypeID)] = [
                ("Byte", sema.types.intType, sema.types.makeNullable(sema.types.intType)),
                ("Short", sema.types.intType, sema.types.makeNullable(sema.types.intType)),
                ("Int", sema.types.intType, sema.types.makeNullable(sema.types.intType)),
                ("Long", sema.types.longType, sema.types.makeNullable(sema.types.longType)),
                ("Float", sema.types.floatType, sema.types.makeNullable(sema.types.floatType)),
                ("Double", sema.types.doubleType, sema.types.makeNullable(sema.types.doubleType)),
            ]
            var checkedCalls = 0
            for (index, testCase) in cases.enumerated() {
                let funcName = ctx.interner.intern("sample\(index)")
                let funcDecl = try #require(ast.arena.decls.compactMap { decl -> FunDecl? in
                    if case let .funDecl(fn) = decl, fn.name == funcName { return fn }
                    return nil
                }.first)
                guard case let .block(callExprs, _) = funcDecl.body else {
                    Issue.record("Expected block body for sample\(index)")
                    continue
                }
                #expect(callExprs.count == 4)
                // x.unaryPlus()
                #expect(sema.bindings.exprType(for: callExprs[0]) == testCase.expectedDirect)
                #expect(sema.bindings.callBinding(for: callExprs[0]) != nil)
                // x.unaryMinus()
                #expect(sema.bindings.exprType(for: callExprs[1]) == testCase.expectedDirect)
                #expect(sema.bindings.callBinding(for: callExprs[1]) != nil)
                // n?.unaryPlus()
                #expect(sema.bindings.exprType(for: callExprs[2]) == testCase.expectedSafe)
                #expect(sema.bindings.callBinding(for: callExprs[2]) != nil)
                // n?.unaryMinus()
                #expect(sema.bindings.exprType(for: callExprs[3]) == testCase.expectedSafe)
                #expect(sema.bindings.callBinding(for: callExprs[3]) != nil)
                checkedCalls += 4
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
