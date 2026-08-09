#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ArraySyntheticMemberLinkTests {
    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    @Test
    func testArrayMemberCallFallbacksResolve() throws {
        let sources: [String] = [
            """
            fun sample0(): Boolean {
                val values = arrayOf(1, 2, 3)
                return values.all { it > 0 }
            }
            """,
            """
            fun sample1() {
                val values = arrayOf(1, 2, 3)
                val result = values.mapIndexed { index, value -> index + value }
                println(result)
            }
            """,
            """
            fun sample2() {
                val values: Array<Int?> = arrayOf(1, null, 2)
                val result = values.filterNotNull()
                println(result)
            }
            """,
            """
            fun sample3(): Int? {
                val values = arrayOf(1, 2, 3)
                return values.firstOrNull()
            }
            """,
            """
            fun sample4(): Int {
                val values = arrayOf(1, 2, 3)
                return values.first()
            }
            """,
            """
            fun sample5(): Int {
                val values = arrayOf(1, 2, 3)
                return values.reduceIndexed { index, acc, value -> acc + value + index }
            }
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let userPaths = ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0) == .user }
            .map { ctx.sourceManager.path(of: $0) }
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)


            // === testArrayOfNullsTopLevelFactoryUsesRuntimeExternalLink ===
            do {
                let symbolID = try #require(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("arrayOfNulls"),
                        ]
                    ),
                    "Expected synthetic arrayOfNulls function to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_of_nulls")
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes == [sema.types.intType])
                #expect(signature.valueParameterHasDefaultValues == [false])
                #expect(signature.valueParameterIsVararg == [false])
                #expect(signature.typeParameterSymbols.count == 1)
                guard case let .classType(returnClass) = sema.types.kind(of: signature.returnType),
                      let arraySymbol = sema.symbols.symbol(returnClass.classSymbol)
                else {
                    Issue.record("Expected arrayOfNulls to return Array<T?>")
                    return
                }
                #expect(ctx.interner.resolve(arraySymbol.name) == "Array")
                #expect(returnClass.args.count == 1)
                guard case let .invariant(elementType) = returnClass.args[0],
                      case let .typeParam(typeParam) = sema.types.kind(of: elementType)
                else {
                    Issue.record("Expected arrayOfNulls element type to be nullable type parameter")
                    return
                }
                #expect(typeParam.symbol == signature.typeParameterSymbols[0])
                #expect(typeParam.nullability == .nullable)
            }

            // === testArrayReversedArrayUsesRuntimeExternalLink ===
            do {
                let symbolID = try #require(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("reversedArray"),
                        ]
                    ),
                    "Expected synthetic Array.reversedArray to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_reversedArray")
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.isEmpty)
                let receiverType = try #require(signature.receiverType)
                #expect(signature.returnType == receiverType)
                #expect(signature.valueParameterHasDefaultValues.isEmpty)
                #expect(signature.valueParameterIsVararg.isEmpty)
                #expect(signature.typeParameterSymbols.count == 1)
            }

            // === testArrayContentDeepToStringUsesRuntimeExternalLink ===
            do {
                let symbolID = try #require(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("contentDeepToString"),
                        ]
                    ),
                    "Expected synthetic Array.contentDeepToString to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_contentDeepToString")
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes == [])
                #expect(signature.returnType == sema.types.stringType)
                #expect(signature.typeParameterSymbols.count == 1)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    Issue.record("Expected Array receiver type")
                    return
                }
                #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
                #expect(receiverClass.args.count == 1)
            }

            // === testArrayContentDeepHashCodeUsesRuntimeExternalLink ===
            do {
                let symbolID = try #require(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("contentDeepHashCode"),
                        ]
                    ),
                    "Expected synthetic Array.contentDeepHashCode to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_contentDeepHashCode")
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes == [])
                #expect(signature.returnType == sema.types.intType)
                #expect(signature.typeParameterSymbols.count == 1)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    Issue.record("Expected Array receiver type")
                    return
                }
                #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
                #expect(receiverClass.args.count == 1)
            }

            // === testArrayContentToStringIsBundledSourceBacked ===
            do {
                // KSP-658: generic Array<T>.contentToString migrated to bundled Kotlin
                // source (kotlin.collections.contentToString); the synthetic Array member
                // stub linking to kk_array_contentToString was removed.
                #expect(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("contentToString"),
                        ]
                    ) == nil,
                    "Generic Array.contentToString synthetic stub should be removed"
                )
                let symbolID = try #require(
                    sema.symbols.lookupAll(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("contentToString"),
                        ]
                    ).first(where: { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.declSite != nil
                        else {
                            return false
                        }
                        return true
                    }),
                    "Expected bundled source Array.contentToString extension"
                )
                #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes == [])
                #expect(signature.returnType == sema.types.stringType)
                #expect(signature.typeParameterSymbols.count == 1)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    Issue.record("Expected Array receiver type")
                    return
                }
                #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
                #expect(receiverClass.args.count == 1)
            }

            // === testArrayContentDeepEqualsUsesRuntimeExternalLink ===
            do {
                let symbolID = try #require(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("contentDeepEquals"),
                        ]
                    ),
                    "Expected synthetic Array.contentDeepEquals to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_contentDeepEquals")
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.count == 1)
                #expect(signature.returnType == sema.types.booleanType)
                #expect(signature.typeParameterSymbols.count == 1)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      case let .classType(parameterClass) = sema.types.kind(of: signature.parameterTypes[0]),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol),
                      let parameterSymbol = sema.symbols.symbol(parameterClass.classSymbol)
                else {
                    Issue.record("Expected Array receiver and parameter types")
                    return
                }
                #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
                #expect(ctx.interner.resolve(parameterSymbol.name) == "Array")
                #expect(receiverClass.args.count == 1)
                #expect(parameterClass.args.count == 1)
            }

            // === testArrayCopyIntoUsesRuntimeExternalLink ===
            do {
                let symbolID = try #require(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("copyInto"),
                        ]
                    ),
                    "Expected synthetic Array.copyInto to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_copyInto")
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.count == 4)
                let receiverType = try #require(signature.receiverType)
                #expect(signature.returnType == receiverType)
                #expect(signature.valueParameterHasDefaultValues == [false, true, true, true])
                #expect(signature.valueParameterIsVararg == [false, false, false, false])
                #expect(signature.typeParameterSymbols.count == 1)
                let parameterNames = signature.valueParameterSymbols.compactMap { symbolID in
                    sema.symbols.symbol(symbolID).map { ctx.interner.resolve($0.name) }
                }
                #expect(parameterNames == ["destination", "destinationOffset", "startIndex", "endIndex"])
            }

            // === testPrimitiveArrayContentToStringOverloadsUseRuntimeExternalLinks ===
            do {
                let expectedLinks = [
                    "IntArray": "kk_intArray_contentToString",
                    "LongArray": "kk_longArray_contentToString",
                    "ByteArray": "kk_byteArray_contentToString",
                    "ShortArray": "kk_shortArray_contentToString",
                    "UIntArray": "kk_uIntArray_contentToString",
                    "ULongArray": "kk_uLongArray_contentToString",
                    "DoubleArray": "kk_doubleArray_contentToString",
                    "FloatArray": "kk_floatArray_contentToString",
                    "BooleanArray": "kk_booleanArray_contentToString",
                    "CharArray": "kk_charArray_contentToString",
                    "UByteArray": "kk_uByteArray_contentToString",
                    "UShortArray": "kk_uShortArray_contentToString",
                ]
                for (arrayName, externalLink) in expectedLinks {
                    let symbolID = try #require(
                        sema.symbols.lookup(
                            fqName: [
                                ctx.interner.intern("kotlin"),
                                ctx.interner.intern(arrayName),
                                ctx.interner.intern("contentToString"),
                            ]
                        ),
                        "Expected \(arrayName).contentToString to be registered"
                    )
                    #expect(sema.symbols.externalLinkName(for: symbolID) == externalLink)
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.parameterTypes == [], "\(arrayName).contentToString should not take parameters")
                    #expect(signature.returnType == sema.types.stringType)
                    guard let receiverType = signature.receiverType,
                          case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                          let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                    else {
                        Issue.record("Expected \(arrayName) receiver type")
                        return
                    }
                    #expect(ctx.interner.resolve(receiverSymbol.name) == arrayName)
                    #expect(receiverClass.args.count == 0)
                }
            }

            // === testPrimitiveArrayJoinToStringOverloadsUseRuntimeExternalLinks ===
            do {
                let expectedLinks = [
                    "IntArray": "kk_intArray_joinToString",
                    "LongArray": "kk_longArray_joinToString",
                    "ByteArray": "kk_byteArray_joinToString",
                    "ShortArray": "kk_shortArray_joinToString",
                    "UIntArray": "kk_uIntArray_joinToString",
                    "ULongArray": "kk_uLongArray_joinToString",
                    "DoubleArray": "kk_doubleArray_joinToString",
                    "FloatArray": "kk_floatArray_joinToString",
                    "BooleanArray": "kk_booleanArray_joinToString",
                    "CharArray": "kk_charArray_joinToString",
                    "UByteArray": "kk_uByteArray_joinToString",
                    "UShortArray": "kk_uShortArray_joinToString",
                ]
                for (arrayName, externalLink) in expectedLinks {
                    let symbolID = try #require(
                        sema.symbols.lookup(
                            fqName: [
                                ctx.interner.intern("kotlin"),
                                ctx.interner.intern(arrayName),
                                ctx.interner.intern("joinToString"),
                            ]
                        ),
                        "Expected \(arrayName).joinToString to be registered"
                    )
                    #expect(sema.symbols.externalLinkName(for: symbolID) == externalLink)
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.parameterTypes == [sema.types.stringType, sema.types.stringType, sema.types.stringType])
                    #expect(signature.valueParameterHasDefaultValues == [true, true, true])
                    #expect(signature.returnType == sema.types.stringType)
                    guard let receiverType = signature.receiverType,
                          case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                          let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                    else {
                        Issue.record("Expected \(arrayName) receiver type")
                        return
                    }
                    #expect(ctx.interner.resolve(receiverSymbol.name) == arrayName)
                    #expect(receiverClass.args.count == 0)
                }
            }

            // === testPrimitiveArrayReversedArrayOverloadsUseRuntimeExternalLink ===
            do {
                let arrayNames = [
                    "IntArray",
                    "LongArray",
                    "ByteArray",
                    "ShortArray",
                    "UIntArray",
                    "ULongArray",
                    "DoubleArray",
                    "FloatArray",
                    "BooleanArray",
                    "CharArray",
                    "UByteArray",
                    "UShortArray",
                ]
                for arrayName in arrayNames {
                    let symbolID = try #require(
                        sema.symbols.lookup(
                            fqName: [
                                ctx.interner.intern("kotlin"),
                                ctx.interner.intern(arrayName),
                                ctx.interner.intern("reversedArray"),
                            ]
                        ),
                        "Expected \(arrayName).reversedArray to be registered"
                    )
                    #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_reversedArray")
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.parameterTypes.isEmpty, "\(arrayName).reversedArray should take no parameters")
                    let receiverType = try #require(signature.receiverType)
                    #expect(signature.returnType == receiverType, "\(arrayName).reversedArray should return the same array type")
                    #expect(signature.valueParameterHasDefaultValues.isEmpty)
                    #expect(signature.valueParameterIsVararg.isEmpty)
                }
            }

            // === testArraySliceArrayOverloadsUseRuntimeExternalLinks ===
            do {
                let symbols = sema.symbols.lookupAll(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("sliceArray"),
                    ]
                )
                let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(links.contains("kk_array_sliceArray_range"))
                #expect(links.contains("kk_array_sliceArray_iterable"))
                for linkName in ["kk_array_sliceArray_range", "kk_array_sliceArray_iterable"] {
                    let symbolID = try #require(
                        symbols.first(where: { sema.symbols.externalLinkName(for: $0) == linkName }),
                        "Expected Array.sliceArray overload linked to \(linkName)"
                    )
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.parameterTypes.count == 1)
                    let receiverType = try #require(signature.receiverType)
                    #expect(signature.returnType == receiverType)
                    #expect(signature.valueParameterHasDefaultValues == [false])
                    #expect(signature.valueParameterIsVararg == [false])
                    #expect(signature.typeParameterSymbols.count == 1)
                }
            }

            // === testPrimitiveArraySliceArrayOverloadsUseRuntimeExternalLinks ===
            do {
                let arrayNames = [
                    "IntArray",
                    "LongArray",
                    "ByteArray",
                    "ShortArray",
                    "UIntArray",
                    "ULongArray",
                    "DoubleArray",
                    "FloatArray",
                    "BooleanArray",
                    "CharArray",
                    "UByteArray",
                    "UShortArray",
                ]
                for arrayName in arrayNames {
                    let symbols = sema.symbols.lookupAll(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern(arrayName),
                            ctx.interner.intern("sliceArray"),
                        ]
                    )
                    let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                    #expect(links.contains("kk_array_sliceArray_range"), "\(arrayName) missing range sliceArray")
                    #expect(links.contains("kk_array_sliceArray_iterable"), "\(arrayName) missing iterable sliceArray")
                    for linkName in ["kk_array_sliceArray_range", "kk_array_sliceArray_iterable"] {
                        let symbolID = try #require(
                            symbols.first(where: { sema.symbols.externalLinkName(for: $0) == linkName }),
                            "Expected \(arrayName).sliceArray overload linked to \(linkName)"
                        )
                        let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                        #expect(signature.parameterTypes.count == 1, "\(arrayName).sliceArray should take one parameter")
                        let receiverType = try #require(signature.receiverType)
                        #expect(signature.returnType == receiverType, "\(arrayName).sliceArray should return the same array type")
                        #expect(signature.valueParameterHasDefaultValues == [false])
                        #expect(signature.valueParameterIsVararg == [false])
                    }
                }
            }

            // === testPrimitiveArrayCopyIntoOverloadsUseRuntimeExternalLink ===
            do {
                let arrayNames = [
                    "IntArray",
                    "LongArray",
                    "ByteArray",
                    "ShortArray",
                    "UIntArray",
                    "ULongArray",
                    "DoubleArray",
                    "FloatArray",
                    "BooleanArray",
                    "CharArray",
                    "UByteArray",
                    "UShortArray",
                ]
                for arrayName in arrayNames {
                    let symbolID = try #require(
                        sema.symbols.lookup(
                            fqName: [
                                ctx.interner.intern("kotlin"),
                                ctx.interner.intern(arrayName),
                                ctx.interner.intern("copyInto"),
                            ]
                        ),
                        "Expected \(arrayName).copyInto to be registered"
                    )
                    #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_copyInto")
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.parameterTypes.count == 4, "\(arrayName).copyInto should take four parameters")
                    let receiverType = try #require(signature.receiverType)
                    #expect(signature.returnType == receiverType, "\(arrayName).copyInto should return destination array type")
                    #expect(signature.valueParameterHasDefaultValues == [false, true, true, true])
                    #expect(signature.valueParameterIsVararg == [false, false, false, false])
                }
            }


        // === testArrayAllFallbackInfersBooleanResult ===
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.all to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[0], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "all"
            }, "Expected Array.all member call")
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.booleanType)
        }

        // === testArrayMapIndexedInfersListResult ===
        // KSP-433: mapIndexed moved to bundled Kotlin source (ArrayHOF.kt), so it
        // resolves as an ordinary `Array<T>.mapIndexed(...): List<R>` extension
        // instead of going through `tryArrayMemberFallback`, whose result type
        // was erased to `Any` with `isCollectionExpr` as the out-of-band signal
        // for downstream KIR/runtime dispatch.
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.mapIndexed to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[1], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "mapIndexed"
            }, "Expected Array.mapIndexed member call")
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(resultClass) = sema.types.kind(of: resultType),
                  let resultSymbol = sema.symbols.symbol(resultClass.classSymbol)
            else {
                Issue.record("Expected Array.mapIndexed to return a List class type")
                return
            }
            #expect(ctx.interner.resolve(resultSymbol.name) == "List")
        }

        // === testArrayFilterNotNullAcceptsZeroArgumentsAndInfersListResult ===
        // See the mapIndexed case above: filterNotNull is bundled Kotlin source
        // (ArrayFilterHOF.kt) since KSP-433, so its result is a real `List<T>`.
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.filterNotNull to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[2], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterNotNull"
            }, "Expected Array.filterNotNull member call")
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(resultClass) = sema.types.kind(of: resultType),
                  let resultSymbol = sema.symbols.symbol(resultClass.classSymbol)
            else {
                Issue.record("Expected Array.filterNotNull to return a List class type")
                return
            }
            #expect(ctx.interner.resolve(resultSymbol.name) == "List")
        }

        // === testArrayFirstOrNullFallbackInfersNullableElementType ===
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.firstOrNull to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[3], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "firstOrNull"
            }, "Expected Array.firstOrNull member call")
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            #expect(sema.types.nullability(of: resultType) == .nullable, "Expected Array.firstOrNull() to infer a nullable result type")
            #expect(sema.types.makeNonNullable(resultType) == sema.types.intType)
        }

        // === testArrayFirstFallbackInfersNonNullElementType ===
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.first to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[4], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "first"
            }, "Expected Array.first member call")
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
        }

        // === testArrayReduceIndexedFallbackInfersElementType ===
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.reduceIndexed to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[5], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "reduceIndexed"
            }, "Expected Array.reduceIndexed member call")
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
        }

    }


}
#endif
