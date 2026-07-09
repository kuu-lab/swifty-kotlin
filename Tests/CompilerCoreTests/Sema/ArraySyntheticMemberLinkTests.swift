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

    @Test func testArrayBinarySearchComparatorOverloadUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(
                sema.symbols.lookupAll(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("binarySearch$compare"),
                    ]
                ).first(where: { sema.symbols.externalLinkName(for: $0) == "kk_array_binarySearch_compare" }),
                "Expected synthetic Array member binarySearch to be registered"
            )
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.parameterTypes.count == 4)
            #expect(signature.valueParameterHasDefaultValues == [false, false, true, true])
            #expect(signature.valueParameterIsVararg == [false, false, false, false])

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                Issue.record("Expected Array receiver type")
                return
            }
            #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
            #expect(receiverClass.args.count == 1)

            guard case let .classType(comparatorType) = sema.types.kind(of: signature.parameterTypes[1]),
                  let comparatorSymbol = sema.symbols.symbol(comparatorType.classSymbol)
            else {
                Issue.record("Expected Comparator parameter type")
                return
            }
            #expect(ctx.interner.resolve(comparatorSymbol.name) == "Comparator")
            #expect(comparatorType.args.count == 1)
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

    @Test func testArrayContentToStringUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("contentToString"),
                    ]
                ),
                "Expected synthetic Array.contentToString to be registered"
            )
            #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_contentToString")

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

    @Test func testArraySortedArrayWithUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("sortedArrayWith"),
                    ]
                ),
                "Expected synthetic Array.sortedArrayWith to be registered"
            )
            #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_sortedArrayWith")

            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.parameterTypes.count == 1)
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [false])
            #expect(signature.typeParameterSymbols.count == 1)

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  case let .classType(returnClass) = sema.types.kind(of: signature.returnType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                Issue.record("Expected Array.sortedArrayWith receiver and return class types")
                return
            }
            #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
            #expect(receiverClass.classSymbol == returnClass.classSymbol)

            guard case let .classType(comparatorType) = sema.types.kind(of: signature.parameterTypes[0]),
                  let comparatorSymbol = sema.symbols.symbol(comparatorType.classSymbol)
            else {
                Issue.record("Expected Comparator parameter type")
                return
            }
            #expect(ctx.interner.resolve(comparatorSymbol.name) == "Comparator")
            #expect(comparatorType.args.count == 1)
        }
    }

    @Test func testArraySortedArrayUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("sortedArray"),
                    ]
                ),
                "Expected synthetic Array.sortedArray to be registered"
            )
            #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_sortedArray")

            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.valueParameterHasDefaultValues == [])
            #expect(signature.valueParameterIsVararg == [])
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.typeParameterUpperBoundsList.count == 1)
            let receiverType = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  case let .classType(returnClass) = sema.types.kind(of: signature.returnType)
            else {
                Issue.record("Expected Array.sortedArray receiver and return class types")
                return
            }
            #expect(receiverClass.classSymbol == returnClass.classSymbol)
        }
    }

    @Test func testArraySortedArrayDescendingUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("sortedArrayDescending"),
                    ]
                ),
                "Expected synthetic Array.sortedArrayDescending to be registered"
            )
            #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_sortedArrayDescending")

            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.valueParameterHasDefaultValues == [])
            #expect(signature.valueParameterIsVararg == [])
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.typeParameterUpperBoundsList.count == 1)
            let receiverType = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  case let .classType(returnClass) = sema.types.kind(of: signature.returnType)
            else {
                Issue.record("Expected Array.sortedArrayDescending receiver and return class types")
                return
            }
            #expect(receiverClass.classSymbol == returnClass.classSymbol)
        }
    }

    @Test func testPrimitiveArraySortedArrayOverloadsUseRuntimeExternalLink() throws {
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
                            ctx.interner.intern("sortedArray"),
                        ]
                    ),
                    "Expected \(arrayName).sortedArray to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_sortedArray")

                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.isEmpty, "\(arrayName).sortedArray should take no parameters")
                let receiverType = try #require(signature.receiverType)
                #expect(signature.returnType == receiverType, "\(arrayName).sortedArray should return the same array type")
                #expect(signature.valueParameterHasDefaultValues.isEmpty)
                #expect(signature.valueParameterIsVararg.isEmpty)
            }
        }
    }

    @Test func testPrimitiveArraySortedArrayDescendingOverloadsUseRuntimeExternalLink() throws {
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
                            ctx.interner.intern("sortedArrayDescending"),
                        ]
                    ),
                    "Expected \(arrayName).sortedArrayDescending to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_sortedArrayDescending")

                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.isEmpty, "\(arrayName).sortedArrayDescending should take no parameters")
                let receiverType = try #require(signature.receiverType)
                #expect(signature.returnType == receiverType, "\(arrayName).sortedArrayDescending should return the same array type")
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
