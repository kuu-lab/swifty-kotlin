#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ArraySyntheticMemberLinkTests {
    @Test func testArrayAllFallbackInfersBooleanResult() throws {
        let source = """
        fun sample(): Boolean {
            val values = arrayOf(1, 2, 3)
            return values.all { it > 0 }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Array.all to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "all"
        }, "Expected Array.all member call")

        #expect(sema.bindings.exprType(for: callExpr) == sema.types.booleanType)
    }

    // MARK: - Array HOF gap fix (mapIndexed/filterIndexed/mapNotNull/filterNot/
    // filterNotNull/reduceIndexed/first/firstOrNull/last/lastOrNull)
    //
    // These previously failed `tryArrayMemberFallback`'s `isSupportedArrayMember`
    // allowlist check outright (KSWIFTK-SEMA-0024 "Unresolved member function"),
    // despite the identically named List members already resolving correctly.
    // See CallTypeChecker+ArrayMemberFallback.swift.

    @Test func testArrayMapIndexedFallbackMarksResultAsCollection() throws {
        // NOTE: like the pre-existing `map`/`filter` Array fallback, mapIndexed's
        // static result type is erased to `Any` (not `List<R>`) at the Sema
        // layer — see `arrayMemberResultType`'s default case in
        // CallTypeChecker+ArrayMemberFallback.swift. `isCollectionExpr` is the
        // out-of-band signal downstream KIR/runtime dispatch relies on instead.
        // Declaring `sample()`'s return type as `List<Int>` here would make this
        // a negative (type-mismatch) test instead, so the result is simply
        // used via a local `val`, not returned under a narrower type.
        let source = """
        fun sample() {
            val values = arrayOf(1, 2, 3)
            val result = values.mapIndexed { index, value -> index + value }
            println(result)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Array.mapIndexed to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "mapIndexed"
        }, "Expected Array.mapIndexed member call")

        #expect(sema.bindings.isCollectionExpr(callExpr), "Expected Array.mapIndexed result to be marked as a collection (List) expression")
    }

    @Test func testArrayFilterNotNullFallbackAcceptsZeroArgumentsAndMarksCollection() throws {
        // See the mapIndexed test above: the Array fallback's result type is
        // erased to `Any`, so this uses a local `val` rather than a `List<Int>`
        // return type to avoid asserting a stronger type guarantee than the
        // fallback actually provides.
        let source = """
        fun sample() {
            val values: Array<Int?> = arrayOf(1, null, 2)
            val result = values.filterNotNull()
            println(result)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Array.filterNotNull to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "filterNotNull"
        }, "Expected Array.filterNotNull member call")

        #expect(sema.bindings.isCollectionExpr(callExpr), "Expected Array.filterNotNull result to be marked as a collection (List) expression")
    }

    @Test func testArrayFirstOrNullFallbackInfersNullableElementType() throws {
        let source = """
        fun sample(): Int? {
            val values = arrayOf(1, 2, 3)
            return values.firstOrNull()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Array.firstOrNull to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "firstOrNull"
        }, "Expected Array.firstOrNull member call")

        let resultType = try #require(sema.bindings.exprType(for: callExpr))
        #expect(sema.types.nullability(of: resultType) == .nullable, "Expected Array.firstOrNull() to infer a nullable result type")
        #expect(sema.types.makeNonNullable(resultType) == sema.types.intType)
    }

    @Test func testArrayFirstFallbackInfersNonNullElementType() throws {
        let source = """
        fun sample(): Int {
            val values = arrayOf(1, 2, 3)
            return values.first()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Array.first to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "first"
        }, "Expected Array.first member call")

        #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
    }

    @Test func testArrayReduceIndexedFallbackInfersElementType() throws {
        let source = """
        fun sample(): Int {
            val values = arrayOf(1, 2, 3)
            return values.reduceIndexed { index, acc, value -> acc + value + index }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Array.reduceIndexed to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "reduceIndexed"
        }, "Expected Array.reduceIndexed member call")

        #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
    }

    @Test func testArrayOfNullsTopLevelFactoryUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testArrayReversedArrayUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testArrayContentDeepToStringUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testArrayContentDeepHashCodeUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testArrayContentToStringIsBundledSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)

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
    }

    @Test func testArrayContentDeepEqualsUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testArrayCopyIntoUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testPrimitiveArrayContentToStringOverloadsUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testPrimitiveArrayJoinToStringOverloadsUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testPrimitiveArrayReversedArrayOverloadsUseRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testArraySliceArrayOverloadsUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testPrimitiveArraySliceArrayOverloadsUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }

    @Test func testPrimitiveArrayCopyIntoOverloadsUseRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
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
    }
}
#endif
