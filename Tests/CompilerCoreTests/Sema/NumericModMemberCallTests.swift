#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NumericModMemberCallTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testNumericModMemberCallsInferKotlinReturnMatrix
            """
            package sample0

                    fun sample(b: Byte, s: Short, i: Int, l: Long, ub: UByte, us: UShort, ui: UInt, ul: ULong, f: Float, d: Double) {
                        l.mod(i)
                        i.mod(l)
                        b.mod(s)
                        ul.mod(ub)
                        ui.mod(us)
                        ub.mod(ul)
                        f.mod(1.5f)
                        f.mod(d)
                        d.mod(f)
                    }

            """,
            // testNumericModRejectsMixedSignedness
            """
            package sample1

                    fun sample(i: Int, l: Long, ui: UInt, ul: ULong) {
                        i.mod(ui)
                        ui.mod(i)
                        l.mod(ul)
                        ul.mod(l)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testNumericModMemberCallsInferKotlinReturnMatrix ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(!sample0Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample0Diagnostics)")

                let modCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, range) = expr,
                          ctx.sourceManager.path(of: range.start.file) == sample0Path,
                          interner.resolve(callee) == "mod"
                    else {
                        return nil
                    }
                    return exprID
                }

                #expect(modCalls.count == 9, "Expected all mod calls to be present")
                let expectedTypes: [TypeID] = [
                    sema.types.intType,
                    sema.types.longType,
                    sema.types.intType,
                    sema.types.ubyteType,
                    sema.types.ushortType,
                    sema.types.ulongType,
                    sema.types.floatType,
                    sema.types.doubleType,
                    sema.types.doubleType,
                ]

                for (exprID, expectedType) in zip(modCalls, expectedTypes) {
                    #expect(sema.bindings.exprTypes[exprID] == expectedType)
                }

            }

            // === testNumericModRejectsMixedSignedness ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(errors.count >= 4, "Expected mixed signedness mod calls to be rejected, got: \(sample1Diagnostics)")

            }

        }
    }

}

#endif
