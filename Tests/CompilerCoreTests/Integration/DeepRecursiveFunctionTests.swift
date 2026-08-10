#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite struct DeepRecursiveFunctionTests {
    @Test func testDeepRecursiveFunction() throws {
        let sources: [String] = [
            // 0: extension callRecursive resolves to suspend overload
            """
            package sample0
            fun wrapper(other: DeepRecursiveFunction<Int, Int>): DeepRecursiveFunction<Int, Int> =
                DeepRecursiveFunction<Int, Int>({ n ->
                    if (n <= 0) 0 else other.callRecursive(n - 1)
                })
            """,

            // 1: top-level initializer parses lambda before next declaration, and compiles to KIR
            """
            package sample1
            val factorial = DeepRecursiveFunction<Int, Int>({ n ->
                if (n <= 1) 1 else n * callRecursive(n - 1)
            })

            fun main1(): Int = factorial(5)
            """,

            // 2: lookup DeepRecursiveFunction / DeepRecursiveScope signatures
            """
            package sample2
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let module = try #require(ctx.kir)

            let sourceFileIDs = try paths.map { path in
                try #require(ctx.sourceManager.fileID(forPath: path))
            }

            // 0: extension callRecursive resolves
            do {
                let sourceFileID = sourceFileIDs[0]
                let sampleDiags = diagnosticsForPath(paths[0], in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

                let resolved = ast.arena.exprs.indices.contains(where: { raw in
                    let exprID = ExprID(rawValue: Int32(raw))
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID,
                          let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr
                    else {
                        return false
                    }
                    guard interner.resolve(callee) == "callRecursive",
                          let callBinding = sema.bindings.callBinding(for: exprID),
                          let symbol = sema.symbols.symbol(callBinding.chosenCallee)
                    else {
                        return false
                    }
                    let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                    return sema.symbols.functionSignature(for: symbol.id)?.isSuspend == true
                        && fqName == "kotlin.DeepRecursiveScope.callRecursive"
                })

                #expect(resolved, "Expected DeepRecursiveScope.callRecursive extension overload to resolve")
            }

            // 1: top-level initializer retains lambda argument and compiles to KIR
            do {
                let sourceFileID = sourceFileIDs[1]
                let sampleDiags = diagnosticsForPath(paths[1], in: ctx)
                #expect(
                    !sampleDiags.contains(where: { $0.severity == .error }),
                    "Expected DeepRecursiveFunction to compile to KIR, got: \(sampleDiags)"
                )

                let parsedInitializer = ast.arena.exprs.indices.contains { raw in
                    let exprID = ExprID(rawValue: Int32(raw))
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID,
                          let expr = ast.arena.expr(exprID),
                          case let .call(calleeID, _, args, _) = expr,
                          args.count == 1,
                          let calleeExpr = ast.arena.expr(calleeID),
                          case let .nameRef(name, _) = calleeExpr
                    else {
                        return false
                    }
                    return interner.resolve(name) == "DeepRecursiveFunction"
                }
                #expect(parsedInitializer, "Expected property initializer call to retain its lambda argument.")

                #expect(module.functionCount >= 1, "Expected at least one KIR function")
            }

            // 2: DeepRecursiveFunction symbols expose expected signatures
            do {
                let invokeFQName = ["kotlin", "DeepRecursiveFunction", "invoke"].map { interner.intern($0) }
                let scopeCallFQName = ["kotlin", "DeepRecursiveScope", "callRecursive"].map { interner.intern($0) }

                let invokeSymbol = try #require(
                    sema.symbols.lookupAll(fqName: invokeFQName).first(where: { symbolID in
                        sema.symbols.symbol(symbolID)?.flags.contains(.operatorFunction) == true
                    })
                )
                let invokeSignature = try #require(sema.symbols.functionSignature(for: invokeSymbol))
                #expect(!(invokeSignature.isSuspend))

                let callRecursiveSymbols = sema.symbols.lookupAll(fqName: scopeCallFQName)
                #expect(callRecursiveSymbols.count == 2, "Expected plain and extension callRecursive overloads")
                #expect(callRecursiveSymbols.allSatisfy { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.isSuspend == true
                })
            }
        }
    }
}
#endif
