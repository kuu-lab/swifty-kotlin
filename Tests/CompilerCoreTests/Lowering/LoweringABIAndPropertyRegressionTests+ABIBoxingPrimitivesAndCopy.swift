#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringABIAndPropertyRegressionTests {
    @Test
    func testABILoweringBoxesAllPrimitiveTypesForAnyParameter() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyNullableType = types.make(.any(.nullable))

        // Define primitives and their expected static boxing callees.
        // .long/.ulong/.double resolve to the "_nonnull" callee variant here
        // because the source TypeKind's nullability is provably `.nonNull`:
        // see BoxingCalleeTable's nonNullOnlyBoxCalleeOverridesByPrimitive.
        let primitives: [(PrimitiveType, KIRExprKind)] = [
            (.byte, .intLiteral(-1)),
            (.short, .intLiteral(240)),
            (.int, .intLiteral(1)),
            (.byte, .intLiteral(1)),
            (.short, .intLiteral(1)),
            (.uint, .uintLiteral(1)),
            (.ubyte, .uintLiteral(1)),
            (.ushort, .uintLiteral(1)),
            (.boolean, .boolLiteral(true)),
            (.long, .longLiteral(1)),
            (.ulong, .ulongLiteral(1)),
            (.float, .floatLiteral(1)),
            (.double, .doubleLiteral(1)),
            (.char, .charLiteral(65)),
        ]

        for (index, (primitive, exprKind)) in primitives.enumerated() {
            let testArena = KIRArena()
            let primType = types.make(.primitive(primitive, .nonNull))

            let callerSym = SymbolID(rawValue: Int32(4000 + index * 10))
            let targetSym = SymbolID(rawValue: Int32(4001 + index * 10))
            let targetParamSym = SymbolID(rawValue: Int32(4002 + index * 10))
            let targetName = interner.intern("accept_\(primitive.rawValue)")

            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
                for: targetSym
            )

            let argExpr = testArena.appendExpr(exprKind, type: primType)
            let resultExpr = testArena.appendExpr(.temporary(1), type: types.unitType)

            let callerFn = KIRFunction(
                symbol: callerSym,
                name: interner.intern("main"),
                params: [],
                returnType: types.unitType,
                body: [
                    .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                    .returnUnit,
                ],
                isSuspend: false,
                isInline: false
            )
            let targetFn = KIRFunction(
                symbol: targetSym,
                name: targetName,
                params: [KIRParameter(symbol: targetParamSym, type: anyNullableType)],
                returnType: types.unitType,
                body: [.returnUnit],
                isSuspend: false,
                isInline: false
            )

            let callerID = testArena.appendDecl(.function(callerFn))
            _ = testArena.appendDecl(.function(targetFn))
            let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: testArena)

            let sema = makeSemaModule(symbols: symbols, types: types).ctx
            try runLowering(module: module, interner: interner, moduleName: "ABIBoxAll_\(index)", sema: sema)

            let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
            let abi = try loweringBoxingABI(.box, for: primitive, nonNull: true, staticPrimitive: true)
            let boxing = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
            #expect(boxing.arguments == [argExpr])
            let boxed = try #require(boxing.result)
            let targetCall = try #require(loweringCalls(in: lowered.body).first { $0.symbol == targetSym })
            #expect(targetCall.arguments == [boxed])
            #expect(boxed != argExpr)
        }
    }

    @Test
    func testABILoweringBoxesCopyFromNonNullIntToNullableIntSlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let fnSym = SymbolID(rawValue: 3800)
        let fromExpr = arena.appendExpr(.intLiteral(5), type: intType)
        let toExpr = arena.appendExpr(.temporary(1), type: nullableIntType)

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyNullableBox"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABICopyNullableBox", sema: sema)

        let lowered = try findKIRFunction(named: "copyNullableBox", in: module, interner: interner)
        let abi = try loweringBoxingABI(.box, for: .int, nonNull: true, staticPrimitive: true)
        let boxing = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        #expect(boxing.arguments == [fromExpr])
        #expect(boxing.result == toExpr)
    }

    @Test
    func testABILoweringKeepsNarrowedIntAssignmentsRaw() throws {
        let source = """
        fun checksum(value: Int): Int {
            var result = value
            result += 2991
            result++
            return result
        }
        fun nullableResult(value: Int): Int? {
            var result: Int? = null
            result = value + 1
            return result
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NarrowedIntCopy", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "checksum", in: module, interner: ctx.interner)
            let narrowCallee = try loweringCompilerCallee("int_narrow", interner: ctx.interner)
            let unboxCallee = ctx.interner.intern(try loweringBoxingABI(.unbox, for: .int, staticPrimitive: true).name)
            let narrowedResults = Set(body.compactMap { instruction -> KIRExprID? in
                guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                      callee == narrowCallee else { return nil }
                return result
            })
            #expect(narrowedResults.count >= 2)
            for instruction in body {
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      callee == unboxCallee else { continue }
                // A raw integer can coincide with a live box address on Linux.
                #expect(arguments.allSatisfy { !narrowedResults.contains($0) },
                        "Narrowed arithmetic results must remain raw when assigned to Int locals")
            }

            let nullableBody = try findKIRFunctionBody(named: "nullableResult", in: module, interner: ctx.interner)
            let boxingABI = try loweringBoxingABI(.box, for: .int, nonNull: true, staticPrimitive: true)
            let boxingCalls = try requireLoweringRuntimeCalls(boxingABI, in: nullableBody, interner: ctx.interner)
            #expect(boxingCalls.allSatisfy { $0.result != nil },
                    "Assignments to nullable Int locals must still box their arithmetic result")
        }
    }

}
#endif
