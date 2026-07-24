#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Mutable-collection, Map, Build, Grouping, and zip/sort/conversion
/// test methods of `ListSyntheticMemberLinkTests`, split out to keep
/// each test source focused.
extension ListSyntheticMemberLinkTests {
    @Test
    func testListSortedAndSortedDescendingHaveComparableUpperBound() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let baseFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]
            let memberCases: [(String, String)] = [
                ("sorted", "kk_list_sorted"),
                ("sortedDescending", "kk_list_sortedDescending"),
            ]

            for (memberName, externalLinkName) in memberCases {
                let symbolID = try #require(sema.symbols.lookupAll(
                        fqName: baseFQName + [ctx.interner.intern(memberName)]
                    ).first(where: { sema.symbols.externalLinkName(for: $0) == externalLinkName }))
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.typeParameterUpperBoundsList.count == 1)
                let upperBounds = signature.typeParameterUpperBoundsList[0]
                #expect(upperBounds.count == 1, "Expected Comparable upper bound for \(memberName) element type")

                guard case let .classType(boundType) = sema.types.kind(of: upperBounds[0]) else {
                    Issue.record("Expected \(memberName) upper bound to be a class type"); return
                }

                #expect(boundType.classSymbol == sema.types.comparableInterfaceSymbol)
                #expect(boundType.args.count == 1)

                guard case let .invariant(argumentType) = boundType.args[0] else {
                    Issue.record("Expected \(memberName) upper bound to reference invariant element type"); return
                }

                let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                )))
                #expect(argumentType == expectedElementType)
            }
        }
    }

    @Test
    func testListSortedAndSortedDescendingRequireComparableElements() throws {
        let source = """
        class Box

        fun render(values: List<Box>) {
            values.sorted()
            values.sortedDescending()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let boundDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-BOUND" }
            #expect(boundDiagnostics.count == 2, "Expected bound diagnostics for sorted/sortedDescending")
        }
    }

    @Test
    func testListConversionMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun convert(values: List<Int>) {
            values.toMutableList()
            values.toSet()
            values.joinToString(", ")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedExternalLinks: [String: String?] = [
                "toMutableList": "kk_list_to_mutable_list",
                "toSet": "kk_list_to_set",
                // KSP-INF-011: List<T>.joinToString is now source-backed
                // (StringSplitJoin.kt) and its body delegates to the private
                // __kk_string_joinToString bridge with external link
                // kk_list_joinToString. The public member itself has no
                // external link name.
                "joinToString": nil,
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                if memberName == "addAll" {
                    let symbol = try #require(sema.symbols.lookup(fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("MutableSet"),
                        ctx.interner.intern(memberName),
                    ]))
                    #expect(sema.symbols.externalLinkName(for: symbol) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                } else {
                    // Exclude bundled stdlib files (FileIDs 0 and 1) to avoid matching
                    // internal calls like `result.add(element)` inside bundled Set HOFs.
                    let callExpr = try #require(firstExprID(in: ast) { id, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        guard ctx.interner.resolve(callee) == memberName else { return false }
                        if let range = ast.arena.exprRange(id), range.start.file.rawValue < 2 {
                            return false
                        }
                        return true
                    })
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                }
            }
        }
    }

    @Test
    func testCollectionAndIterableConversionMembersUseRuntimeExternalLinks() throws {
        let cases: [SyntheticMemberCallCase] = [
            .init(
                source: """
                fun copy(values: Collection<String>) {
                    values.toMutableList()
                }
                """,
                memberName: "toMutableList",
                expectedExternalLink: "kk_collection_toMutableList",
                expectedTypeShape: .classNamed("MutableList")
            ),
            .init(
                source: """
                fun copy(values: Collection<String>) {
                    values.toTypedArray()
                }
                """,
                memberName: "toTypedArray",
                expectedExternalLink: "kk_collection_toTypedArray",
                expectedTypeShape: .classNamed("Array")
            ),
            .init(
                source: """
                fun copy(values: Iterable<String>) {
                    values.toMutableList()
                }
                """,
                memberName: "toMutableList",
                expectedExternalLink: "kk_iterable_toMutableList",
                expectedTypeShape: .classNamed("MutableList")
            ),
            .init(
                source: """
                fun copy(values: Iterable<String>) {
                    values.toMutableSet()
                }
                """,
                memberName: "toMutableSet",
                expectedExternalLink: "kk_iterable_toMutableSet",
                expectedTypeShape: .classNamed("MutableSet")
            ),
        ]

        for testCase in cases {
            try assertSyntheticMemberCall(testCase)
        }
    }

    @Test
    func testSetBinaryMembersKeepSetResultTypeInFallbackPath() throws {
        let source = """
        fun combine(values: Set<Int>, other: Set<Int>) {
            val left = values.intersect(other)
            val middle = values.union(other)
            val right = values.subtract(other)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedMembers = Set(["intersect", "union", "subtract"])
            let setResultTypes: [String: TypeID] = Dictionary(uniqueKeysWithValues: ast.arena.exprs.indices.compactMap { index in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr
                else {
                    return nil
                }
                let memberName = ctx.interner.resolve(callee)
                guard expectedMembers.contains(memberName),
                      let type = sema.bindings.exprType(for: exprID)
                else {
                    return nil
                }
                return (memberName, type)
            })

            #expect(setResultTypes.keys.count == expectedMembers.count)

            for memberName in expectedMembers {
                let type = try #require(setResultTypes[memberName])
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    Issue.record("Expected \(memberName) to infer as Set<Int>, got \(sema.types.kind(of: type))"); return
                }
                #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Set")
                #expect(classType.args.count == 1, "Expected Set<Int> type argument for \(memberName)")
                let elementType: TypeID
                switch classType.args[0] {
                case let .invariant(type), let .out(type), let .in(type):
                    elementType = type
                case .star:
                    Issue.record("Expected concrete Set element projection for \(memberName)"); return
                }
                #expect(sema.types.kind(of: elementType) == .primitive(.int, .nonNull))
            }
        }
    }

    @Test
    func testListUnzipUsesRuntimeExternalLinkAndReturnsPairOfLists() throws {
        let source = """
        fun split(values: List<Pair<Int, String>>) {
            val result: Pair<List<Int>, List<String>> = values.unzip()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.unzip to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "unzip"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_unzip")

            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(pairType) = sema.types.kind(of: resultType) else {
                Issue.record("Expected List.unzip to return Pair<List<Int>, List<String>>"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(pairType.classSymbol)?.name)) == "Pair")
            #expect(pairType.args.count == 2)

            let firstListType = try projectedType(pairType.args[0])
            let secondListType = try projectedType(pairType.args[1])
            try assertListType(firstListType, elementType: sema.types.intType, sema: sema, interner: ctx.interner)
            try assertListType(secondListType, elementType: sema.types.stringType, sema: sema, interner: ctx.interner)
        }
    }

    @Test
    func testSequenceJoinToStringUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            println(values.joinToString(", "))
            println(values.joinToString(prefix = "<", postfix = ">"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                guard ctx.interner.resolve(callee) == "joinToString" else { return false }
                // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                // List<String>.joinToString(...) internally; exclude bundled
                // call sites so this finds the user's Sequence.joinToString(...).
                return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_sequence_joinToString")
        }
    }

    @Test
    func testSequenceReduceIndexedOrNullUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            println(values.reduceIndexedOrNull { index, acc, value -> acc + index * value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try #require(ctx.sema)
            let sequenceReduceIndexedOrNullSymbol = try #require(sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("sequences"),
                        ctx.interner.intern("Sequence"),
                        ctx.interner.intern("reduceIndexedOrNull"),
                    ]
                ))
            #expect(sema.symbols.externalLinkName(for: sequenceReduceIndexedOrNullSymbol) == "kk_sequence_reduceIndexedOrNull")
        }
    }

    @Test
    func testListFlatMapBindsToBundledSource() throws {
        let source = """
        fun render(values: List<String>) {
            val result: List<Int> = values.flatMap { listOf(it.length) }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try #require(ctx.sema)
            let sourceFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("flatMap"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: sourceFQName)
            let listFlatMapSymbol = try #require(symbols.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      let (receiverClassType, _) = resolveClassTypeSymbol(receiverType, sema: sema),
                      let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol)
                else { return false }
                return ctx.interner.resolve(receiverSymbol.name) == "List"
            }, "Expected bundled source List.flatMap overload")

            let symbolInfo = try #require(sema.symbols.symbol(listFlatMapSymbol))
            #expect(!symbolInfo.flags.contains(.synthetic), "flatMap must be a bundled source declaration")
            #expect(sema.symbols.externalLinkName(for: listFlatMapSymbol) == nil, "source flatMap must not link to runtime")

            let symbol = listFlatMapSymbol
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
            else {
                Issue.record("Expected List.flatMap to return List<R>"); return
            }
            #expect(ctx.interner.resolve(returnSymbol.name) == "List")

            let transformType = try #require(signature.parameterTypes.first)
            guard case let .functionType(functionType) = sema.types.kind(of: transformType),
                  let (_, transformReturnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
            else {
                Issue.record("Expected List.flatMap transform to return List<R>"); return
            }
            #expect(ctx.interner.resolve(transformReturnSymbol.name) == "List")
        }
    }

    @Test
    func testSequenceFlatMapIndexedRegistersIterableAndSequenceOverloads() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            val iterableResult = values.flatMapIndexed { index, value -> listOf(index, value * 10) }
            val sequenceResult = values.flatMapIndexed { index, value -> sequenceOf(index + value, value * 100) }
            println(iterableResult.toList())
            println(sequenceResult.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try #require(ctx.sema)
            let memberFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("flatMapIndexed"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: memberFQName)
            #expect(symbols.count == 2, "Expected Iterable and Sequence flatMapIndexed overloads")
            #expect(symbols.allSatisfy {
                sema.symbols.externalLinkName(for: $0) == "kk_sequence_flatMapIndexed"
            })

            let transformReturnTypeNames = symbols.compactMap { symbolID -> String? in
                guard let parameterType = sema.symbols.functionSignature(for: symbolID)?.parameterTypes.first,
                      case let .functionType(functionType) = sema.types.kind(of: parameterType),
                      let (_, returnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
                else { return nil }
                return ctx.interner.resolve(returnSymbol.name)
            }
            #expect(transformReturnTypeNames.contains("Iterable"))
            #expect(transformReturnTypeNames.contains("Sequence"))
        }
    }

    @Test
    func testSequenceShuffledUsesRuntimeExternalLinks() throws {
        let source = """
        import kotlin.random.Random

        fun render(values: Sequence<Int>) {
            values.shuffled()
            values.shuffled(Random)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try #require(ctx.sema)
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("shuffled"),
            ]
            let externalLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                sema.symbols.externalLinkName(for: $0)
            })
            #expect(externalLinks.contains("kk_sequence_shuffled"))
            #expect(externalLinks.contains("kk_sequence_shuffled_random"))
        }
    }

    @Test
    func testSequenceRequireNoNullsSyntheticStubHasRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int?>) {
            val result: Sequence<Int> = values.requireNoNulls()
            println(result.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try #require(ctx.sema)
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("requireNoNulls"),
            ]
            #expect(sema.symbols.lookupAll(fqName: fqName).contains { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_sequence_requireNoNulls"
            })
        }
    }

    @Test
    func testMutableListMutationMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.add(1)
            values.add(1, 0)
            values.addAll(listOf(2, 3))
            values.removeAll(listOf(4))
            values.retainAll(listOf(5))
            values.removeAt(0)
            values.removeFirst()
            values.removeFirstOrNull()
            values.removeLast()
            values.removeLastOrNull()
            values.clear()
            values.fill(9)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedExternalLinks: [(String, Int, String)] = [
                ("add", 1, "kk_mutable_list_add"),
                ("add", 2, "kk_mutable_list_add_at"),
                ("addAll", 1, "kk_mutable_list_addAll"),
                ("removeAll", 1, "kk_mutable_list_removeAll"),
                ("retainAll", 1, "kk_mutable_list_retainAll"),
                ("removeAt", 1, "kk_mutable_list_removeAt"),
                ("removeFirst", 0, "kk_mutable_list_removeFirst"),
                ("removeFirstOrNull", 0, "kk_mutable_list_removeFirstOrNull"),
                ("removeLast", 0, "kk_mutable_list_removeLast"),
                ("removeLastOrNull", 0, "kk_mutable_list_removeLastOrNull"),
                ("clear", 0, "kk_mutable_list_clear"),
                ("fill", 1, "kk_mutable_list_fill"),
            ]

            for (memberName, argumentCount, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, valueArgs, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && valueArgs.count == argumentCount
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName)/\(argumentCount) to resolve to \(externalLinkName)")
            }
        }
    }

    @Test
    func testMutableListBulkMutationFallbacksReturnBoolean() throws {
        let source = """
        fun mutate(): Boolean {
            val values = listOf(1, 2, 3).toMutableList()
            return values.addAll(listOf(4))
                || values.removeAll(listOf(5))
                || values.retainAll(listOf(1, 2))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                let symbolID = try #require(sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("MutableList"),
                            ctx.interner.intern(memberName),
                        ]
                    ))

                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_mutable_list_\(memberName)", "Expected \(memberName) to resolve to runtime extern")
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.booleanType, "Expected \(memberName) to return Boolean")
                #expect(!(sema.bindings.isCollectionExpr(callExpr)), "Expected \(memberName) result to remain a scalar Boolean")
            }
        }
    }

    @Test
    func testMutableCollectionSequenceAddAllMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun appendCollection(collection: MutableCollection<Int>, source: Sequence<Int>) = collection.addAll(source)
        fun appendList(list: MutableList<Int>, source: Sequence<Int>) = list.addAll(source)
        fun appendSet(set: MutableSet<Int>, source: Sequence<Int>) = set.addAll(source)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedExternalLinks = [
                "collection": "kk_mutable_collection_addAll_sequence",
                "list": "kk_mutable_list_addAll_sequence",
                "set": "kk_mutable_set_addAll_sequence",
            ]

            for (receiverName, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(receiver, callee, _, valueArgs, _) = expr,
                          ctx.interner.resolve(callee) == "addAll",
                          valueArgs.count == 1,
                          case let .nameRef(name, _) = ast.arena.expr(receiver)
                    else {
                        return false
                    }
                    return ctx.interner.resolve(name) == receiverName
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(receiverName).addAll(Sequence) to resolve to \(externalLinkName)")
                #expect(sema.bindings.exprType(for: callExpr) == sema.types.booleanType)
            }
        }
    }

    @Test
    func testMutableListSortMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.sort()
            values.sortWith { a, b -> b - a }
            values.sortBy { it }
            values.sortByDescending { it }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
            let expectedExternalLinks = [
                "sort": "kk_mutable_list_sort",
                "sortWith": "kk_mutable_list_sortWith",
                "sortBy": "kk_mutable_list_sortBy",
                "sortByDescending": "kk_mutable_list_sortByDescending",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                if let chosenCallee = sema.bindings.callBinding(for: callExpr)?.chosenCallee {
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                }
            }
        }
    }

    @Test
    func testListPrimitiveArrayConversionsUseRuntimeExternalLinks() throws {
        let cases: [SyntheticMemberCallCase] = [
            .init(
                source: """
                fun convert(values: List<Boolean>) {
                    values.toBooleanArray()
                }
                """,
                memberName: "toBooleanArray",
                expectedExternalLink: "kk_list_toBooleanArray",
                expectedTypeShape: .classNamed("BooleanArray")
            ),
            .init(
                source: """
                fun convert(values: List<Byte>) {
                    values.toByteArray()
                }
                """,
                memberName: "toByteArray",
                expectedExternalLink: "kk_list_toByteArray",
                expectedTypeShape: .classNamed("ByteArray")
            ),
            .init(
                source: """
                fun convert(values: List<Short>) {
                    values.toShortArray()
                }
                """,
                memberName: "toShortArray",
                expectedExternalLink: "kk_list_toShortArray",
                expectedTypeShape: .classNamed("ShortArray")
            ),
            .init(
                source: """
                fun convert(values: List<Int>) {
                    values.toIntArray()
                }
                """,
                memberName: "toIntArray",
                expectedExternalLink: "kk_list_toIntArray",
                expectedTypeShape: .classNamed("IntArray")
            ),
            .init(
                source: """
                fun convert(values: List<Double>) {
                    values.toDoubleArray()
                }
                """,
                memberName: "toDoubleArray",
                expectedExternalLink: "kk_list_toDoubleArray",
                expectedTypeShape: .classNamed("DoubleArray")
            ),
            .init(
                source: """
                fun convert(values: List<Float>) {
                    values.toFloatArray()
                }
                """,
                memberName: "toFloatArray",
                expectedExternalLink: "kk_list_toFloatArray",
                expectedTypeShape: .classNamed("FloatArray")
            ),
        ]

        for testCase in cases {
            try assertSyntheticMemberCall(testCase)
        }
    }

    @Test
    func testMutableListBulkMutationMembersUseInvariantReceiverTypes() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let ownerFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbolID = try #require(sema.symbols.lookup(fqName: ownerFQName + [interner.intern(memberName)]))
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                guard case let .classType(receiverType) = sema.types.kind(of: try #require(signature.receiverType)) else {
                    Issue.record("Expected \(memberName) to use MutableList receiver type"); return
                }
                guard case .invariant = try #require(receiverType.args.first) else {
                    Issue.record("Expected \(memberName) receiver projection to remain invariant"); return
                }
            }
        }
    }

    @Test
    func testMutableListBulkCollectionMembersAcceptCollectionOfSameElementType() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(3, 4))
            values.retainAll(listOf(5, 6))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedExternalLinks = [
                "addAll": "kk_mutable_list_addAll",
                "removeAll": "kk_mutable_list_removeAll",
                "retainAll": "kk_mutable_list_retainAll",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
            }
        }
    }

    @Test
    func testMutableListBulkCollectionMembersKeepInvariantReceiverType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let mutableListFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbolID = try #require(sema.symbols.lookup(fqName: mutableListFQName + [ctx.interner.intern(memberName)]))
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                let receiverType = try #require(signature.receiverType)
                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                    Issue.record("Expected \(memberName) receiver to be a class type"); return
                }
                guard case .invariant = try #require(receiverClassType.args.first) else {
                    Issue.record("Expected \(memberName) receiver to keep invariant element type, got \(sema.types.renderType(receiverType))"); return
                }

                let parameterType = try #require(signature.parameterTypes.first)
                guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected \(memberName) parameter to be a class type"); return
                }
                guard case .out = try #require(parameterClassType.args.first) else {
                    Issue.record("Expected \(memberName) parameter to remain covariant Collection<out E>, got \(sema.types.renderType(parameterType))"); return
                }
            }
        }
    }

    @Test
    func testOutProjectedMutableListBlocksBulkMutationMembers() throws {
        let source = """
        fun mutate(values: MutableList<out Number>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(3, 4))
            values.retainAll(listOf(5, 6))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-VAR-OUT" }
            #expect(diagnostics.count == 3, "Projected MutableList bulk writes should be rejected")
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    @Test
    func testListSortMembersRemainUnavailableOnImmutableList() throws {
        let source = """
        fun mutate(values: List<Int>) {
            values.sort()
            values.sortBy { it }
            values.sortByDescending { it }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in ["sort", "sortBy", "sortByDescending"] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil, "Expected immutable List.\(memberName) to remain unresolved")
            }

            #expect(!(ctx.diagnostics.diagnostics.isEmpty), "Expected diagnostics for immutable List.sort* calls")
        }
    }

    @Test
    func testMutableListBulkOperationsAcceptListArguments() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(1))
            values.retainAll(listOf(2))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    @Test
    func testMutableListMatchesTransitiveCollectionConstraint() throws {
        let source = """
        fun <T> consume(values: Collection<T>): T? = values.firstOrNull()

        fun demo(values: MutableList<Int>): Int? = consume(values)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let consumeCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "consume"
            })

            #expect(sema.bindings.callBinding(for: consumeCall)?.chosenCallee != nil, "Expected MutableList<Int> to satisfy Collection<T> through transitive lifting")
        }
    }

    @Test
    func testListIteratorMemberResolvesWithoutTypeConstraintFailure() throws {
        let source = """
        class IntContainer(private val elements: List<Int>) {
            operator fun iterator(): Iterator<Int> = elements.iterator()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let iteratorCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "iterator"
            })

            let chosenCallee = try #require(sema.bindings.callBinding(for: iteratorCall)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_range_iterator")
        }
    }

    /// Regression: listOf(...).contains/isEmpty must not emit KSWIFTK-SEMA-VAR-OUT.
    /// The synthetic List type uses .out projection; variance relaxation must apply.
    @Test
    func testListOfContainsAndIsEmptyDoNotEmitVarOut() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.contains(2)
            list.contains(5)
            list.isEmpty()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var containsCalls: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "contains"
                else { continue }
                containsCalls.append(exprID)
            }
            #expect(containsCalls.count == 2)
            for callID in containsCalls {
                let binding = sema.bindings.callBinding(for: callID)
                #expect(binding?.chosenCallee != nil, "contains should resolve")
                if let chosen = binding?.chosenCallee {
                    #expect(sema.symbols.externalLinkName(for: chosen) == nil, "List.contains is source-backed and should have no external link")
                }
            }
        }
    }

    @Test
    func testListElementAtUsesRuntimeExternalLink() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.elementAt(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "elementAt"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_elementAt")
        }
    }

    @Test
    func testListElementAtOrNullUsesRuntimeExternalLink() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.elementAtOrNull(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "elementAtOrNull"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_elementAtOrNull")
        }
    }

    @Test
    func testSetMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun check(values: Set<Int>) {
            values.contains(42)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "contains"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_set_contains", "Expected contains to resolve to kk_set_contains")
        }
    }

    @Test
    func testSetRegistersCollectionAsNominalSupertype() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let setSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
            ]))
            let collectionSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Collection"),
            ]))

            #expect(sema.types.directNominalSupertypes(for: setSymbol) == [collectionSymbol], "Expected Set to register Collection as its nominal supertype")
        }
    }

    @Test
    func testContainsAllMembersUseCollectionRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("List")]))
            let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")]))

            func containsAllSymbol(owner: SymbolID) -> SymbolID? {
                let name = ctx.interner.intern("containsAll")
                func matches(_ symbolID: SymbolID) -> Bool {
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: receiverType)
                    else {
                        return false
                    }
                    return classType.classSymbol == owner
                }
                if let sourceBacked = sema.symbols.lookupAll(fqName: collectionsPkg + [name]).first(where: matches) {
                    return sourceBacked
                }
                guard let ownerSymbol = sema.symbols.symbol(owner) else { return nil }
                return sema.symbols.lookupAll(fqName: ownerSymbol.fqName + [name]).first(where: matches)
            }

            let listContainsAll = try #require(containsAllSymbol(owner: listSymbol), "Expected List.containsAll source extension")
            let setContainsAll = try #require(containsAllSymbol(owner: setSymbol), "Expected Set.containsAll")

            // List.containsAll is source-backed (KSP-423); Set.containsAll still uses the runtime bridge.
            #expect(sema.symbols.externalLinkName(for: listContainsAll) == nil)
            #expect(sema.symbols.externalLinkName(for: setContainsAll) == "kk_set_containsAll")
        }
    }

    @Test
    func testSetContainsAllUsesCollectionParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let setContainsAll = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
                ctx.interner.intern("containsAll"),
            ]))
            let signature = try #require(sema.symbols.functionSignature(for: setContainsAll))
            let parameterType = try #require(signature.parameterTypes.first)

            guard case let .classType(collectionType) = sema.types.kind(of: parameterType) else {
                Issue.record("Set.containsAll should accept Collection<E>"); return
            }

            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(collectionType.classSymbol)?.name)) == "Collection")
            guard case let .out(elementType) = try #require(collectionType.args.first) else {
                Issue.record("Collection parameter should preserve the element projection"); return
            }
            let typeParamSymbol = try #require(signature.typeParameterSymbols.first)
            let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            #expect(elementType == expectedElementType)
        }
    }

    @Test
    func testContainsMembersAreMarkedOperatorFunctions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("List")]))
            let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")]))

            func containsSymbol(owner: SymbolID, packageFQName: [InternedString]) -> SymbolID? {
                let name = ctx.interner.intern("contains")
                func matches(_ symbolID: SymbolID) -> Bool {
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: receiverType)
                    else {
                        return false
                    }
                    return classType.classSymbol == owner
                }
                if let sourceBacked = sema.symbols.lookupAll(fqName: packageFQName + [name]).first(where: matches) {
                    return sourceBacked
                }
                guard let ownerSymbol = sema.symbols.symbol(owner) else { return nil }
                return sema.symbols.lookupAll(fqName: ownerSymbol.fqName + [name]).first(where: matches)
            }

            let listContains = try #require(containsSymbol(owner: listSymbol, packageFQName: collectionsPkg))
            let setContains = try #require(containsSymbol(owner: setSymbol, packageFQName: collectionsPkg))
            #expect(sema.symbols.symbol(listContains)?.flags.contains(.operatorFunction) == true)
            #expect(sema.symbols.symbol(setContains)?.flags.contains(.operatorFunction) == true)

            let stringContains = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("text"),
                ctx.interner.intern("contains"),
            ]))
            #expect(sema.symbols.symbol(stringContains)?.flags.contains(.operatorFunction) == true)
        }
    }

    @Test
    func testWithIndexUsesIterableOfIndexedValueSignature() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let withIndexSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("withIndex"),
            ]))
            let indexedValueSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("IndexedValue"),
            ]))
            let indexedValueRecord = try #require(sema.symbols.symbol(indexedValueSymbol))
            #expect(indexedValueRecord.kind == .class)
            #expect(indexedValueRecord.flags.contains(.dataType))

            let signature = try #require(sema.symbols.functionSignature(for: withIndexSymbol))
            guard case let .classType(iterableType) = sema.types.kind(of: signature.returnType) else {
                Issue.record("Expected withIndex() to return Iterable<IndexedValue<T>>"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(iterableType.classSymbol)?.name)) == "Iterable")
            guard case let .out(elementType) = try #require(iterableType.args.first),
                  case let .classType(indexedValueType) = sema.types.kind(of: elementType)
            else {
                Issue.record("Expected Iterable element type to be IndexedValue"); return
            }
            #expect(indexedValueType.classSymbol == indexedValueSymbol)
        }
    }

    @Test
    func testMutableSetMutationMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableSet<Int>) {
            values.add(1)
            values.remove(1)
            values.addAll(listOf(2, 3))
            values.addAll(setOf(2, 3))
            values.clear()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)

            let expectedExternalLinks = [
                "add": "kk_mutable_set_add",
                "remove": "kk_mutable_set_remove",
                "addAll": "kk_mutable_set_addAll",
                "clear": "kk_mutable_set_clear",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let symbol = try #require(sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern("MutableSet"),
                    ctx.interner.intern(memberName),
                ]))
                #expect(sema.symbols.externalLinkName(for: symbol) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
            }

            let addAllSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableSet"),
                ctx.interner.intern("addAll"),
            ]))
            #expect(sema.symbols.externalLinkName(for: addAllSymbol) == "kk_mutable_set_addAll", "Expected addAll to resolve to kk_mutable_set_addAll")
        }
    }

    @Test
    func testMutableListBulkMutationMembersUseInvariantReceiverType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let mutableListFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbol = try #require(sema.symbols.lookup(fqName: mutableListFQName + [ctx.interner.intern(memberName)]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                let receiverType = try #require(signature.receiverType)

                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                      let firstArg = receiverClassType.args.first
                else {
                    Issue.record("Expected MutableList.\(memberName) receiver to be a class type"); return
                }

                guard case .invariant = firstArg else {
                    Issue.record("Expected MutableList.\(memberName) receiver to remain invariant"); return
                }
            }
        }
    }

    @Test
    func testMutableSetClearIsNotMarkedOperatorFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let clearSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableSet"),
                ctx.interner.intern("clear"),
            ]))

            #expect(!(sema.symbols.symbol(clearSymbol)?.flags.contains(.operatorFunction) == true), "MutableSet.clear should not be registered as an operator function")
        }
    }

    @Test
    func testMutableSetAddAllUsesCollectionParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let symbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableSet"),
                interner.intern("addAll"),
            ]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            let parameterType = try #require(signature.parameterTypes.first)

            guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                Issue.record("Expected MutableSet.addAll to take a collection type"); return
            }
            #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Collection")
            guard case let .out(elementType) = try #require(classType.args.first),
                  case .typeParam = sema.types.kind(of: elementType)
            else {
                Issue.record("Expected MutableSet.addAll parameter to use Collection<out E>"); return
            }
        }
    }

    @Test
    func testMutableCollectionArrayAddAllOverloadsUseRuntimeExternalLinks() throws {
        let cases: [(String, String, String)] = [
            (
                "MutableCollection",
                "kk_mutable_collection_addAll",
                "fun mutate(values: MutableCollection<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
            (
                "MutableList",
                "kk_mutable_list_addAll",
                "fun mutate(values: MutableList<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
            (
                "MutableSet",
                "kk_mutable_set_addAll",
                "fun mutate(values: MutableSet<Int>) { values.addAll(arrayOf(1, 2)) }"
            ),
        ]

        for (receiverName, expectedExternalLink, source) in cases {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                let ast = try #require(ctx.ast)
                let sema = try #require(ctx.sema)
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                    guard ctx.interner.resolve(callee) == "addAll" else { return false }
                    // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                    // MutableList<String>.addAll(...) internally; exclude
                    // bundled call sites so this finds the user's call.
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)

                #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedExternalLink, "Expected \(receiverName).addAll(Array) to resolve to \(expectedExternalLink)")

                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let parameterType = try #require(signature.parameterTypes.first)
                guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected \(receiverName).addAll(Array) to take an Array parameter"); return
                }
                #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Array")
            }
        }
    }

    @Test
    func testMutableCollectionIterableAddAllOverloadsUseRuntimeExternalLinks() throws {
        let cases: [(String, String, String)] = [
            (
                "MutableCollection",
                "kk_mutable_collection_addAll_iterable",
                "fun mutate(values: MutableCollection<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
            (
                "MutableList",
                "kk_mutable_list_addAll_iterable",
                "fun mutate(values: MutableList<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
            (
                "MutableList sequence as Iterable",
                "kk_mutable_list_addAll_iterable",
                "fun mutate(values: MutableList<Int>) { values.addAll(sequenceOf(1).asIterable()) }"
            ),
            (
                "MutableSet",
                "kk_mutable_set_addAll_iterable",
                "fun mutate(values: MutableSet<Int>, source: Iterable<Int>) { values.addAll(source) }"
            ),
        ]

        for (receiverName, expectedExternalLink, source) in cases {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                let ast = try #require(ctx.ast)
                let sema = try #require(ctx.sema)
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                    guard ctx.interner.resolve(callee) == "addAll" else { return false }
                    // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                    // MutableList<String>.addAll(...) internally; exclude
                    // bundled call sites so this finds the user's call.
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)

                #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedExternalLink, "Expected \(receiverName).addAll(Iterable) to resolve to \(expectedExternalLink)")

                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let parameterType = try #require(signature.parameterTypes.first)
                guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected \(receiverName).addAll(Iterable) to take an Iterable parameter"); return
                }
                #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Iterable")
            }
        }
    }

    /// Map member calls (containsKey, put, remove) go through the collection-fallback
    /// inference path which does not record a callBinding. Instead we verify that the
    /// synthetic symbols in the symbol table carry the correct external link names.
    @Test
    func testMapSyntheticSymbolsHaveCorrectExternalLinkNames() throws {
        let source = """
        fun noop() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let kotlinCollections = ["kotlin", "collections"].map { interner.intern($0) }
            let mapFQ = kotlinCollections + [interner.intern("Map")]
            let mutableMapFQ = kotlinCollections + [interner.intern("MutableMap")]

            // KSP-430: Map higher-order functions are source-backed in
            // MapHOF.kt, so only non-migrated Map members appear here.
            let expectedLinks: [(fqName: [InternedString], memberName: String, externalLink: String)] = [
                (mapFQ, "containsKey", "kk_map_contains_key"),
                (mapFQ, "containsValue", "kk_map_contains_value"),
                (mapFQ, "keys", "kk_map_keys"),
                (mapFQ, "values", "kk_map_values"),
                (mapFQ, "entries", "kk_map_entries"),
                (mapFQ, "getValue", "kk_map_getValue"),
                (mapFQ, "withDefault", "kk_map_withDefault"),
                (mapFQ, "toList", "kk_map_toList"),
                (mapFQ, "toMutableMap", "kk_map_to_mutable_map"),
                (mutableMapFQ, "put", "kk_mutable_map_put"),
                (mutableMapFQ, "remove", "kk_mutable_map_remove"),
                (mutableMapFQ, "putAll", "kk_mutable_map_putAll"),
            ]

            for (ownerFQ, memberName, expectedExternal) in expectedLinks {
                let memberFQ = ownerFQ + [interner.intern(memberName)]
                let symbolID = try #require(sema.symbols.lookup(fqName: memberFQ))
                #expect(sema.symbols.externalLinkName(for: symbolID) == expectedExternal, "Expected \(memberName) to have external link \(expectedExternal)")
            }
        }
    }

    @Test
    func testMapWithDefaultSurfaceResolvesDefaultLambda() throws {
        let source = """
        fun probe(values: Map<Int, Int>): Int {
            val defaults = values.withDefault { it * 10 }
            return defaults.getValue(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected Map.withDefault surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testIndexedAndAggregateListMembersAreInlineSynthetic() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let listFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]

            // forEachIndexed remains synthetic; mapIndexed / filterIndexed / sumOf are bundled source.
            for memberName in ["forEachIndexed"] {
                let symbolID = try #require(sema.symbols.lookup(fqName: listFQName + [ctx.interner.intern(memberName)]))
                let flags = try #require(sema.symbols.symbol(symbolID)?.flags)
                #expect(flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
                #expect(flags.contains(.synthetic), "Expected \(memberName) to be synthetic")
            }
        }
    }

    @Test
    func testListFilterIndexedUsesBundledSource() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            list.filterIndexed { index, value -> index + value > 20 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIndexed"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("filterIndexed"),
            ])
        }
    }

    @Test
    func testListFilterIsInstanceUsesBundledSource() throws {
        let source = """
        fun main() {
            val list: List<Any> = listOf(1, "two", 3)
            list.filterIsInstance<Int>()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIsInstance"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("filterIsInstance"),
            ])
        }
    }

    @Test
    func testListFilterHOFsUseBundledSourceCalls() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 30)
            val nullable: List<Int?> = listOf(1, null, 3)
            val mixed: List<Any> = listOf(1, "two", 3)
            values.filter { value -> value > 10 }
            values.filterNot { value -> value == 20 }
            nullable.filterNotNull()
            values.filterIndexed { index, value -> index + value > 20 }
            mixed.filterIsInstance<Int>()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            for name in ["filter", "filterNot", "filterNotNull", "filterIndexed", "filterIsInstance"] {
                let callExpr = try #require(memberCallExprIDs(named: name, in: ast, interner: ctx.interner).last)
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern(name),
                ])
            }
        }
    }

    @Test
    func testMapHigherOrderMembersAreInlineAndToListPreservesPairType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let packageFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
            ]
            let mapFQName = packageFQName + [interner.intern("Map")]

            func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                case let .classType(classType):
                    return sema.symbols.symbol(classType.classSymbol)?.fqName
                default:
                    return nil
                }
            }

            for memberName in ["forEach", "map", "filter", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo"] {
                let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern(memberName)]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          nominalOwnerFQName(for: receiverType) == mapFQName
                    else {
                        return false
                    }
                    return true
                }
                let symbolID = try #require(candidates.first, "Expected bundled source for Map.\(memberName)")
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                #expect(symbol.fqName == packageFQName + [interner.intern(memberName)])
            }

            let toListSymbol = try #require(sema.symbols.lookup(fqName: mapFQName + [interner.intern("toList")]))
            let toListSignature = try #require(sema.symbols.functionSignature(for: toListSymbol))
            guard case let .classType(listType) = sema.types.kind(of: toListSignature.returnType) else {
                Issue.record("Expected Map.toList to return List<Pair<K, V>>"); return
            }
            let listName = try #require(sema.symbols.symbol(listType.classSymbol)?.name)
            #expect(interner.resolve(listName) == "List")
            let firstListArg = try #require(listType.args.first)
            guard case let .out(pairTypeID) = firstListArg,
                  case let .classType(pairType) = sema.types.kind(of: pairTypeID)
            else {
                Issue.record("Expected Map.toList element type to be Pair"); return
            }
            let pairName = try #require(sema.symbols.symbol(pairType.classSymbol)?.name)
            #expect(interner.resolve(pairName) == "Pair")
        }
    }

    @Test
    func testMapEntryToPairSurfaceIsRegistered() throws {
        let source = """
        fun probe(values: Map<String, Int>): List<Pair<String, Int>> {
            return values.map { it.toPair() }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected Map.Entry.toPair surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let sema = try #require(ctx.sema)
            let entryFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Map"),
                ctx.interner.intern("Entry"),
            ]
            let toPairSymbol = try #require(sema.symbols.lookup(fqName: entryFQName + [ctx.interner.intern("toPair")]))
            #expect(sema.symbols.externalLinkName(for: toPairSymbol) == "kk_map_entry_to_pair")
            let signature = try #require(sema.symbols.functionSignature(for: toPairSymbol))
            guard case let .classType(pairType) = sema.types.kind(of: signature.returnType) else {
                Issue.record("Expected Map.Entry.toPair to return Pair<K, V>"); return
            }
            let pairName = try #require(sema.symbols.symbol(pairType.classSymbol)?.name)
            #expect(ctx.interner.resolve(pairName) == "Pair")
            #expect(pairType.args.count == 2)
        }
    }

    @Test
    func testBuildListInfersElementTypeFromBuilderCalls() throws {
        let source = """
        fun render(): List<Int> = buildList {
            this.add(1)
            add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildListCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildList"
            })
            let buildListType = try #require(sema.bindings.exprType(for: buildListCall))
            guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                Issue.record("Expected buildList(...) to produce a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
            guard case let .out(elementType) = try #require(listType.args.first) else {
                Issue.record("Expected List element type argument"); return
            }
            #expect(elementType == sema.types.intType)

            // Use lastExprID to skip bundled stdlib's thisRef expressions
            let explicitThis = try #require(lastExprID(in: ast) { _, expr in
                if case .thisRef = expr { return true }
                return false
            })
            let explicitThisType = try #require(sema.bindings.exprType(for: explicitThis))
            guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                Issue.record("Expected builder receiver to be a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(receiverType.classSymbol)?.name)) == "MutableList")
            guard case let .invariant(receiverElementType) = try #require(receiverType.args.first) else {
                Issue.record("Expected MutableList element type argument"); return
            }
            #expect(receiverElementType == sema.types.intType)
        }
    }

    @Test
    func testBuildMapInfersKeyAndValueTypesFromBuilderCalls() throws {
        let source = """
        fun render(): Map<String, Int> = buildMap {
            this.put("a", 1)
            put("b", 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildMapCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildMap"
            })
            let buildMapType = try #require(sema.bindings.exprType(for: buildMapCall))
            guard case let .classType(mapType) = sema.types.kind(of: buildMapType) else {
                Issue.record("Expected buildMap(...) to produce a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(mapType.classSymbol)?.name)) == "Map")
            guard mapType.args.count >= 2,
                  case let .out(keyType) = mapType.args[0],
                  case let .out(valueType) = mapType.args[1]
            else {
                Issue.record("Expected Map key/value type arguments"); return
            }
            #expect(keyType == sema.types.stringType)
            #expect(valueType == sema.types.intType)

            // Use lastExprID to skip bundled stdlib's thisRef expressions
            let explicitThis = try #require(lastExprID(in: ast) { _, expr in
                if case .thisRef = expr { return true }
                return false
            })
            let explicitThisType = try #require(sema.bindings.exprType(for: explicitThis))
            guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                Issue.record("Expected builder receiver to be a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(receiverType.classSymbol)?.name)) == "MutableMap")
            guard receiverType.args.count >= 2,
                  case let .invariant(receiverKeyType) = receiverType.args[0],
                  case let .invariant(receiverValueType) = receiverType.args[1]
            else {
                Issue.record("Expected MutableMap key/value type arguments"); return
            }
            #expect(receiverKeyType == sema.types.stringType)
            #expect(receiverValueType == sema.types.intType)
        }
    }

    @Test
    func testMapKeysToResolvesWithMutableMapDestination() throws {
        let source = """
        fun remap(values: Map<Int, String>, destination: MutableMap<Int, String>): MutableMap<Int, String> {
            return values.mapKeysTo(destination) { entry -> entry.key + 10 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Map.mapKeysTo surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let packageFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
            ]
            let mapFQName = packageFQName + [interner.intern("Map")]

            func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                case let .classType(classType):
                    return sema.symbols.symbol(classType.classSymbol)?.fqName
                default:
                    return nil
                }
            }

            let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern("mapKeysTo")]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      nominalOwnerFQName(for: receiverType) == mapFQName
                else {
                    return false
                }
                return true
            }
            let symbol = try #require(candidates.first, "Expected bundled source for Map.mapKeysTo")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            #expect(sema.symbols.symbol(symbol)?.fqName == packageFQName + [interner.intern("mapKeysTo")])

            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.parameterTypes.count == 2)
            #expect(signature.returnType == signature.parameterTypes[0])
        }
    }

    @Test
    func testMapValuesToResolvesWithMutableMapDestination() throws {
        let source = """
        fun remap(values: Map<Int, String>, destination: MutableMap<Int, Int>): MutableMap<Int, Int> {
            return values.mapValuesTo(destination) { entry -> entry.value.length }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Map.mapValuesTo surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let packageFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
            ]
            let mapFQName = packageFQName + [interner.intern("Map")]

            func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                case let .classType(classType):
                    return sema.symbols.symbol(classType.classSymbol)?.fqName
                default:
                    return nil
                }
            }

            let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern("mapValuesTo")]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      nominalOwnerFQName(for: receiverType) == mapFQName
                else {
                    return false
                }
                return true
            }
            let symbol = try #require(candidates.first, "Expected bundled source for Map.mapValuesTo")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            #expect(sema.symbols.symbol(symbol)?.fqName == packageFQName + [interner.intern("mapValuesTo")])

            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.parameterTypes.count == 2)
            #expect(signature.returnType == signature.parameterTypes[0])
        }
    }

    @Test
    func testMutableMapPutAllUsesProjectedMapParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let symbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableMap"),
                interner.intern("putAll"),
            ]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            let parameterType = try #require(signature.parameterTypes.first)

            guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                Issue.record("Expected MutableMap.putAll to take a map type"); return
            }
            #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Map")
            guard classType.args.count == 2,
                  case let .out(keyType) = classType.args[0],
                  case let .out(valueType) = classType.args[1],
                  case .typeParam = sema.types.kind(of: keyType),
                  case .typeParam = sema.types.kind(of: valueType)
            else {
                Issue.record("Expected MutableMap.putAll parameter to use projected Map<K, V>"); return
            }
        }
    }

    @Test
    func testGroupingEachCountToUsesProjectedMutableMapParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let symbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Grouping"),
                interner.intern("eachCountTo"),
            ]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(sema.symbols.externalLinkName(for: symbol) == "kk_grouping_eachCountTo")
            #expect(signature.parameterTypes.count == 1)
            #expect(signature.returnType == signature.parameterTypes[0])

            let receiverType = try #require(signature.receiverType)
            guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                Issue.record("Expected Grouping.eachCountTo receiver to be a class type"); return
            }
            #expect(try interner.resolve(#require(sema.symbols.symbol(receiverClassType.classSymbol)?.name)) == "Grouping")

            let parameterType = try #require(signature.parameterTypes.first)
            guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                Issue.record("Expected eachCountTo to take a MutableMap type"); return
            }
            #expect(try interner.resolve(#require(sema.symbols.symbol(parameterClassType.classSymbol)?.name)) == "MutableMap")
            #expect(parameterClassType.args.count == 2)
            guard case let .in(keyProjection) = parameterClassType.args[0],
                  case .typeParam = sema.types.kind(of: keyProjection),
                  case let .invariant(valueType) = parameterClassType.args[1]
            else {
                Issue.record("Expected eachCountTo parameter to use MutableMap<in K, Int>"); return
            }
            #expect(valueType == sema.types.intType)
        }
    }

    @Test
    func testBuildListCapacityOverloadResolves() throws {
        let source = """
        fun render(): List<Int> = buildList(4) {
            add(1)
            add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildListCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildList"
            })
            let buildListType = try #require(sema.bindings.exprType(for: buildListCall))
            guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                Issue.record("Expected buildList(capacity) to produce a class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
            guard case let .out(elementType) = try #require(listType.args.first) else {
                Issue.record("Expected List element type argument"); return
            }
            #expect(elementType == sema.types.intType)
        }
    }

    @Test
    func testListZipWithNextOverloadsInferReturnTypes() throws {
        let source = """
        fun pairs(values: List<Int>) = values.zipWithNext()
        fun gaps(values: List<Int>) = values.zipWithNext { left, right -> right - left }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.zipWithNext overloads to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            func projectedType(_ projection: TypeArg) -> TypeID? {
                switch projection {
                case let .invariant(type), let .out(type), let .in(type):
                    return type
                case .star:
                    return nil
                }
            }

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let noArgCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zipWithNext" && args.isEmpty
            })
            let transformCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zipWithNext" && args.count == 1
            })

            let noArgType = try #require(sema.bindings.exprType(for: noArgCall))
            guard case let .classType(noArgListType) = sema.types.kind(of: noArgType),
                  let pairType = projectedType(try #require(noArgListType.args.first)),
                  case let .classType(pairClassType) = sema.types.kind(of: pairType)
            else {
                Issue.record("Expected zipWithNext() to return List<Pair<Int, Int>>"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(noArgListType.classSymbol)?.name)) == "List")
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(pairClassType.classSymbol)?.name)) == "Pair")
            #expect(pairClassType.args.compactMap(projectedType) == [sema.types.intType, sema.types.intType])

            let transformType = try #require(sema.bindings.exprType(for: transformCall))
            guard case let .classType(transformListType) = sema.types.kind(of: transformType),
                  let transformElementType = projectedType(try #require(transformListType.args.first))
            else {
                Issue.record("Expected zipWithNext(transform) to return List<Int>"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(transformListType.classSymbol)?.name)) == "List")
            #expect(transformElementType == sema.types.intType)
        }
    }

    @Test
    func testListZipUsesRuntimeExternalLinkAndReturnsPairList() throws {
        let source = """
        fun zipValues(values: List<Int>, labels: List<String>) = values.zip(labels)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.zip to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "zip" && args.count == 1
            })

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            let fileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListWindowChunk.kt")

            let callType = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(listType) = sema.types.kind(of: callType) else {
                Issue.record("Expected List.zip to return a List type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
            let pairType: TypeID
            switch try #require(listType.args.first) {
            case let .invariant(type), let .out(type), let .in(type):
                pairType = type
            case .star:
                Issue.record("Expected List.zip to return a concrete Pair projection"); return
            }
            guard case let .classType(pairClassType) = sema.types.kind(of: pairType) else {
                Issue.record("Expected List.zip to return List<Pair<Int, String>>, got \(sema.types.kind(of: pairType))"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(pairClassType.classSymbol)?.name)) == "Pair")
            #expect(pairClassType.args.count == 2)

            let firstArgument: TypeID
            switch pairClassType.args[0] {
            case let .invariant(type), let .out(type), let .in(type):
                firstArgument = type
            case .star:
                Issue.record("Expected concrete Pair first argument"); return
            }
            let secondArgument: TypeID
            switch pairClassType.args[1] {
            case let .invariant(type), let .out(type), let .in(type):
                secondArgument = type
            case .star:
                Issue.record("Expected concrete Pair second argument"); return
            }
            #expect(firstArgument == sema.types.intType)
            #expect(secondArgument == sema.types.stringType)
        }
    }

    @Test
    func testStringAsIterableImplicitReceiverDoesNotExposeListOnlyMembers() throws {
        let source = """
        fun probe(): Char = with("hello") {
            asIterable().get(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    @Test
    func testListFlatMapIndexedBindsToBundledSource() throws {
        let source = """
        fun render(values: List<String>) {
            val result: List<Int> = values.flatMapIndexed { index, value -> listOf(index + value.length) }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try #require(ctx.sema)
            let sourceFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("flatMapIndexed"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: sourceFQName)
            let listFlatMapIndexedSymbol = try #require(symbols.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      let (receiverClassType, _) = resolveClassTypeSymbol(receiverType, sema: sema),
                      let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol)
                else { return false }
                return ctx.interner.resolve(receiverSymbol.name) == "List"
            }, "Expected bundled source List.flatMapIndexed overload")

            let symbolInfo = try #require(sema.symbols.symbol(listFlatMapIndexedSymbol))
            #expect(!symbolInfo.flags.contains(.synthetic), "flatMapIndexed must be a bundled source declaration")
            #expect(sema.symbols.externalLinkName(for: listFlatMapIndexedSymbol) == nil, "source flatMapIndexed must not link to runtime")

            let symbol = listFlatMapIndexedSymbol
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
            else {
                Issue.record("Expected List.flatMapIndexed to return List<R>"); return
            }
            #expect(ctx.interner.resolve(returnSymbol.name) == "List")

            let transformType = try #require(signature.parameterTypes.first)
            guard case let .functionType(functionType) = sema.types.kind(of: transformType),
                  let (_, transformReturnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
            else {
                Issue.record("Expected List.flatMapIndexed transform to return List<R>"); return
            }
            #expect(functionType.params.count == 2, "Expected flatMapIndexed transform to take (index, element)")
            #expect(functionType.params.first == sema.types.intType)
            #expect(functionType.params.last != sema.types.intType, "Second transform parameter should be the list element type, not Int")
            #expect(ctx.interner.resolve(transformReturnSymbol.name) == "List")
        }
    }

    @Test
    func testListToBooleanArrayUsesRuntimeExternalLink() throws {
        let source = """
        fun convert(values: List<Boolean>) {
            values.toBooleanArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toBooleanArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toBooleanArray")
            let resultType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toBooleanArray to return BooleanArray"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "BooleanArray")
        }
    }

    @Test
    func testListToShortArrayUsesRuntimeExternalLink() throws {
        let source = """
        fun convert(values: List<Short>) {
            values.toShortArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toShortArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toShortArray")
            let resultType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toShortArray to return ShortArray"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "ShortArray")
        }
    }

    @Test
    func testListToDoubleArrayUsesRuntimeExternalLink() throws {
        let source = """
        fun convert(values: List<Double>) {
            values.toDoubleArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toDoubleArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toDoubleArray")
            let resultType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toDoubleArray to return DoubleArray"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "DoubleArray")
        }
    }

    @Test
    func testListToFloatArrayUsesRuntimeExternalLink() throws {
        let source = """
        fun convert(values: List<Float>) {
            values.toFloatArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toFloatArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toFloatArray")
            let resultType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toFloatArray to return FloatArray"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "FloatArray")
        }
    }
}
#endif
