#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ListSyntheticMemberLinkTests {
    @Test
    func testListLastIndexExtensionPropertyResolvesToRuntimeGetter() throws {
        let source = """
        import kotlin.collections.lastIndex

        fun last(values: List<String>): Int {
            return values.lastIndex
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.lastIndex to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let propertyExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "lastIndex" && args.isEmpty
            })
            #expect(sema.bindings.exprType(for: propertyExpr) == sema.types.intType)

            let getter = try #require(sema.bindings.callBinding(for: propertyExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: getter) == "kk_list_lastIndex")

            let property = try #require(sema.bindings.identifierSymbol(for: propertyExpr))
            #expect(sema.symbols.externalLinkName(for: property) == "kk_list_lastIndex")
            #expect(sema.symbols.propertyType(for: property) == sema.types.intType)
        }
    }

    @Test
    func testListTransformMembersUseRuntimeExternalLinksForParameterReceivers() throws {
        let source = """
        import kotlin.random.Random

        fun render(values: List<Int>) {
            values.take(3)
            values.drop(2)
            values.reversed()
            values.sorted()
            values.distinct()
            values.shuffled()
            values.shuffled(Random)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedExternalLinks = [
                ("take", 1, "kk_list_take"),
                ("drop", 1, "kk_list_drop"),
                ("reversed", 0, "kk_list_reversed"),
                ("sorted", 0, "kk_list_sorted"),
                ("distinct", 0, "kk_list_distinct"),
                ("shuffled", 0, "kk_list_shuffled"),
                ("shuffled", 1, "kk_list_shuffled_random"),
            ]

            for (memberName, argumentCount, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && args.count == argumentCount
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
            }
        }
    }

    @Test
    func testListAndCollectionConversionMembersUseRuntimeExternalLinks() throws {
        let cases: [SyntheticMemberCallCase] = [
            .init(
                source: """
                fun copy(values: List<Pair<String, Int>>) {
                    values.toMap()
                }
                """,
                memberName: "toMap",
                expectedExternalLink: "kk_list_toMap",
                expectedTypeShape: .classNamed("Map")
            ),
            .init(
                source: """
                fun copy(values: Collection<String>): List<String> {
                    return values.toList()
                }
                """,
                memberName: "toList",
                expectedExternalLink: "kk_collection_toList",
                expectedTypeShape: .classNamed("List")
            ),
            .init(
                source: """
                fun copy(values: List<String>): MutableSet<String> {
                    return values.toHashSet()
                }
                """,
                memberName: "toHashSet",
                expectedExternalLink: "kk_list_toHashSet",
                expectedTypeShape: nil
            ),
        ]

        for testCase in cases {
            try assertSyntheticMemberCall(testCase)
        }
    }

    @Test
    func testListIndicesExtensionPropertyResolvesToRuntimeGetter() throws {
        let source = """
        import kotlin.collections.indices
        import kotlin.ranges.IntRange

        fun range(values: List<String>): IntRange {
            return values.indices
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.indices to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let propertyExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "indices" && args.isEmpty
            })
            let propertyType = try #require(sema.bindings.exprType(for: propertyExpr))
            guard case let .classType(rangeType) = sema.types.kind(of: propertyType) else {
                Issue.record("Expected List.indices to have IntRange type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(rangeType.classSymbol)?.name)) == "IntRange")

            let getter = try #require(sema.bindings.callBinding(for: propertyExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: getter) == "kk_list_indices")

            let property = try #require(sema.bindings.identifierSymbol(for: propertyExpr))
            #expect(sema.symbols.externalLinkName(for: property) == "kk_list_indices")
            #expect(sema.symbols.propertyType(for: property) == propertyType)
        }
    }

    @Test
    func testArrayListOfFactoryInfersMutableListType() throws {
        let source = """
        fun probe() {
            val values = arrayListOf(1, 2)
            values.add(3)
            val typed: ArrayList<Int> = arrayListOf<Int>()
            typed.add(4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected arrayListOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let arrayListCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "arrayListOf"
            })
            let callType = try #require(sema.bindings.exprTypes[arrayListCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected arrayListOf to produce a MutableList class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableList")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(arrayListCall), "Expected arrayListOf to be tracked as a collection expression")
        }
    }

    @Test
    func testLinkedSetOfFactoryInfersLinkedHashSetType() throws {
        let source = """
        fun probe() {
            val values = linkedSetOf(1, 2)
            values.add(3)
            val typed: LinkedHashSet<Int> = linkedSetOf<Int>()
            typed.add(4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected linkedSetOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let linkedSetCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "linkedSetOf"
            })
            let callType = try #require(sema.bindings.exprTypes[linkedSetCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected linkedSetOf to produce a LinkedHashSet class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "LinkedHashSet")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(linkedSetCall), "Expected linkedSetOf to be tracked as a collection expression")
        }
    }

    @Test
    func testLinkedHashSetConcreteClassAndConstructorSurfaceIsRegistered() throws {
        let source = """
        fun probe() {
            val constructed: LinkedHashSet<Int> = LinkedHashSet<Int>()
            val asMutable: MutableSet<Int> = constructed
            val fromExpectedMutable: MutableSet<Int> = LinkedHashSet()
            constructed.add(1)
            asMutable.add(2)
            fromExpectedMutable.add(3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected LinkedHashSet concrete class calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let kotlinCollections = [interner.intern("kotlin"), interner.intern("collections")]
            let linkedHashSetFQ = kotlinCollections + [interner.intern("LinkedHashSet")]
            let mutableSetFQ = kotlinCollections + [interner.intern("MutableSet")]
            let linkedHashSetSymbol = try #require(sema.symbols.lookup(fqName: linkedHashSetFQ))
            let mutableSetSymbol = try #require(sema.symbols.lookup(fqName: mutableSetFQ))

            let linkedHashSetInfo = try #require(sema.symbols.symbol(linkedHashSetSymbol))
            #expect(linkedHashSetInfo.kind == .class)
            #expect(linkedHashSetInfo.flags.contains(.synthetic))
            #expect(linkedHashSetInfo.flags.contains(.openType))
            #expect(sema.symbols.directSupertypes(for: linkedHashSetSymbol).contains(mutableSetSymbol))
            #expect(sema.types.nominalTypeParameterVariances(for: linkedHashSetSymbol) == [.invariant])

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: linkedHashSetFQ + [interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .public)
            #expect(sema.symbols.externalLinkName(for: constructorSymbol) == "__kk_emptySet")
            let signature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.classTypeParameterCount == 1)

            let constructorCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return interner.resolve(name) == "LinkedHashSet"
            })
            let callType = try #require(sema.bindings.exprTypes[constructorCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected LinkedHashSet constructor to produce a class type"); return
            }
            #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "LinkedHashSet")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(constructorCall), "Expected LinkedHashSet constructor to be tracked as a collection expression")
        }
    }

    @Test
    func testLinkedMapOfFactoryInfersMutableMapType() throws {
        let source = """
        fun probe() {
            val values = linkedMapOf("a" to 1)
            values.put("b", 2)
            val typed: LinkedHashMap<String, Int> = linkedMapOf<String, Int>()
            typed.put("c", 3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected linkedMapOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let linkedMapCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "linkedMapOf"
            })
            let callType = try #require(sema.bindings.exprTypes[linkedMapCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected linkedMapOf to produce a MutableMap class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableMap")
            #expect(classType.args == [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(linkedMapCall), "Expected linkedMapOf to be tracked as a collection expression")
        }
    }

    @Test
    func testHashMapOfFactoryInfersMutableMapType() throws {
        let source = """
        fun probe() {
            val values = hashMapOf("a" to 1)
            values.put("b", 2)
            val typed: HashMap<String, Int> = hashMapOf<String, Int>()
            typed.put("c", 3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected hashMapOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let hashMapCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "hashMapOf"
            })
            let callType = try #require(sema.bindings.exprTypes[hashMapCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected hashMapOf to produce a MutableMap class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableMap")
            #expect(classType.args == [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(hashMapCall), "Expected hashMapOf to be tracked as a collection expression")
        }
    }

    @Test
    func testHashSetOfFactoryInfersMutableSetType() throws {
        let source = """
        fun probe() {
            val values = hashSetOf(1, 2)
            values.add(3)
            val typed: HashSet<Int> = hashSetOf<Int>()
            typed.add(4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected hashSetOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let hashSetCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "hashSetOf"
            })
            let callType = try #require(sema.bindings.exprTypes[hashSetCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected hashSetOf to produce a MutableSet class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableSet")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(hashSetCall), "Expected hashSetOf to be tracked as a collection expression")
        }
    }

    @Test
    func testListAggregateMembersUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let expectedExternalLinks = [
                "sum": "kk_list_sum",
                // sumOf / minByOrNull / maxByOrNull are bundled Kotlin source (KSP-002).
                "maxOfWith": "kk_list_maxOfWith",
                "minOfWith": "kk_list_minOfWith",
                "minBy": "kk_list_minBy",
                "maxOfWithOrNull": "kk_list_maxOfWithOrNull",
                "maxWithOrNull": "kk_list_maxWithOrNull",
                "min": "kk_list_min",
                "maxWith": "kk_list_maxWith",
                "maxOrNull": "kk_list_maxOrNull",
                "minOrNull": "kk_list_minOrNull",
                "minOf": "kk_list_minOf",
                "maxBy": "kk_list_maxBy",
                "minOfWithOrNull": "kk_list_minOfWithOrNull",
                "maxOfOrNull": "kk_list_maxOfOrNull",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let symbolID = try #require(sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("List"),
                            ctx.interner.intern(memberName),
                        ]
                    ))
                #expect(sema.symbols.externalLinkName(for: symbolID) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
            }

            // find / findLast are source-backed in ListSearchHOF.kt (KSP-423)
            // and therefore have no external link name.
            let collectionsPkg = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            for memberName in ["find", "findLast"] {
                let sourceSymbols = sema.symbols.lookupAll(fqName: collectionsPkg + [ctx.interner.intern(memberName)]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.receiverType != nil
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_")
                }
                #expect(!sourceSymbols.isEmpty, "Expected bundled Kotlin source for List.\(memberName)")
                #expect(sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil }, "List.\(memberName) should be source-backed")
            }
        }
    }

    @Test
    func testBundledListAggregateHOFsSuppressSyntheticStubs() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let packageFQName = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let listOwnerFQName = packageFQName + [ctx.interner.intern("List")]
            let iterableOwnerFQName = packageFQName + [ctx.interner.intern("Iterable")]

            func bundledListExtensionSymbols(named name: String, arity: Int) -> [SymbolID] {
                let fqName = packageFQName + [ctx.interner.intern(name)]
                return sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == arity,
                          signature.receiverType != nil
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_")
                }
            }

            func syntheticMemberSymbols(
                ownerFQName: [InternedString],
                name: String,
                arity: Int,
                externalLinkPrefix: String? = nil
            ) -> [SymbolID] {
                let memberFQName = ownerFQName + [ctx.interner.intern(name)]
                return sema.symbols.lookupAll(fqName: memberFQName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          symbol.flags.contains(.synthetic),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == arity
                    else {
                        return false
                    }
                    if let externalLinkPrefix,
                       let link = sema.symbols.externalLinkName(for: symbolID)
                    {
                        return link.hasPrefix(externalLinkPrefix)
                    }
                    return externalLinkPrefix == nil
                }
            }

            for name in ["count", "any", "all"] {
                let bundled = bundledListExtensionSymbols(named: name, arity: 1)
                #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)(predicate)")
                for symbolID in bundled {
                    #expect(
                        sema.symbols.externalLinkName(for: symbolID) == nil,
                        "Bundled List.\(name) should not have an external link name"
                    )
                }
            }

            for name in ["sumOf", "maxByOrNull", "minByOrNull"] {
                let synthetic = syntheticMemberSymbols(
                    ownerFQName: listOwnerFQName,
                    name: name,
                    arity: 1,
                    externalLinkPrefix: "kk_list_"
                )
                #expect(
                    synthetic.isEmpty,
                    "Expected no synthetic List.\(name) stub when bundled Kotlin source exists, found \(synthetic.count)"
                )
            }

            let sourceBackedFilters: [(name: String, arity: Int)] = [
                ("filter", 1),
                ("filterNot", 1),
                ("filterNotNull", 0),
                ("filterIndexed", 1),
                ("filterIsInstance", 0),
            ]
            for (name, arity) in sourceBackedFilters {
                let bundled = bundledListExtensionSymbols(named: name, arity: arity)
                #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)")
                #expect(
                    bundled.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                    "Bundled List.\(name) should not have an external link name"
                )
                let synthetic = syntheticMemberSymbols(
                    ownerFQName: listOwnerFQName,
                    name: name,
                    arity: arity,
                    externalLinkPrefix: "kk_list_"
                )
                #expect(
                    synthetic.isEmpty,
                    "Expected no synthetic List.\(name) stub when bundled Kotlin source exists, found \(synthetic.count)"
                )
            }

            // KSP-423: search and predicate HOFs are source-backed.
            let sourceBackedSearchHOFs: [(name: String, arity: Int)] = [
                ("contains", 1),
                ("containsAll", 1),
                ("lastIndexOf", 1),
                ("count", 0),
                ("count", 1),
                ("any", 0),
                ("any", 1),
                ("all", 1),
                ("none", 0),
                ("none", 1),
            ]
            for (name, arity) in sourceBackedSearchHOFs {
                let bundled = bundledListExtensionSymbols(named: name, arity: arity)
                #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)(arity: \(arity))")
                #expect(
                    bundled.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                    "Bundled List.\(name) should not have an external link name"
                )
                let synthetic = syntheticMemberSymbols(
                    ownerFQName: listOwnerFQName,
                    name: name,
                    arity: arity,
                    externalLinkPrefix: "kk_list_"
                )
                #expect(
                    synthetic.isEmpty,
                    "Expected no synthetic List.\(name)(arity: \(arity)) stub when bundled Kotlin source exists, found \(synthetic.count)"
                )
            }

            for (name, link) in [("any", "kk_iterable_any"), ("all", "kk_iterable_all")] {
                let synthetic = syntheticMemberSymbols(
                    ownerFQName: iterableOwnerFQName,
                    name: name,
                    arity: 1,
                    externalLinkPrefix: link
                )
                #expect(
                    synthetic.isEmpty,
                    "Expected no synthetic Iterable.\(name)(predicate) stub when bundled List.\(name) exists"
                )
            }

            #expect(
                syntheticMemberSymbols(ownerFQName: listOwnerFQName, name: "count", arity: 1).isEmpty
            )
            #expect(
                syntheticMemberSymbols(ownerFQName: iterableOwnerFQName, name: "count", arity: 1).isEmpty
            )
        }
    }

    @Test
    func testListSearchHOFsHaveBundledSourceDefinitions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let packageFQName = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let expectedArities: [String: Set<Int>] = [
                "first": [0, 1],
                "firstOrNull": [0, 1],
                "last": [0, 1],
                "lastOrNull": [0, 1],
                "single": [0, 1],
                "singleOrNull": [0, 1],
                "find": [1],
                "findLast": [1],
                "indexOf": [1],
                "indexOfFirst": [1],
                "indexOfLast": [1],
                "lastIndexOf": [1],
                "contains": [1],
                "containsAll": [1],
                "count": [0, 1],
                "any": [0, 1],
                "all": [1],
                "none": [0, 1],
            ]

            for (name, arities) in expectedArities {
                let fqName = packageFQName + [ctx.interner.intern(name)]
                let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID)
                    else {
                        return false
                    }
                    let path = ctx.sourceManager.path(of: fileID)
                    return path.hasPrefix("__bundled_")
                }
                let registeredArities = Set(sourceSymbols.compactMap { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count
                })
                #expect(arities.isSubset(of: registeredArities), "Expected \(name) bundled source overloads \(arities), got \(registeredArities)")
                #expect(sourceSymbols.allSatisfy { symbolID in
                        sema.symbols.functionSignature(for: symbolID)?.receiverType != nil
                    }, "Expected \(name) bundled source definitions to be List extension functions")
            }
        }
    }

    @Test
    func testListFilterIsInstanceToBindsBundledSource() throws {
        let source = """
        fun collect(values: List<Any>, dest: MutableList<String>) {
            values.filterIsInstanceTo(dest)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.filterIsInstanceTo to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIsInstanceTo"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.symbols.symbol(chosenCallee)?.declSite != nil)
            #expect(sema.bindings.isCollectionExpr(callExpr), "Expected filterIsInstanceTo result to be tracked as a collection expression")
        }
    }

    @Test
    func testIterableSumByResolvesToListRuntime() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Int {
            return values.sumBy { value ->
                value * value
            }
        }

        fun checksumFromList(values: List<Int>): Int {
            return values.sumBy(selector = { value ->
                value * 2
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.sumBy surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "sumBy"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_sumBy")
            #expect(sema.symbols.annotations(for: memberSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" }, "Iterable.sumBy should carry Deprecated metadata")

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.sumBy selector parameter to be a function"); return
            }
            #expect(selectorType.params.count == 1)
            #expect(signature.returnType == sema.types.intType)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            #expect(callLinks.filter { $0 == "kk_list_sumBy" }.count == 2)
        }
    }

    @Test
    func testIterableSumByDoubleResolvesToListRuntime() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Double {
            return values.sumByDouble { value ->
                if (value == 2) 1.5 else 0.25
            }
        }

        fun checksumFromList(values: List<Int>): Double {
            return values.sumByDouble(selector = { value ->
                value.toDouble()
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.sumByDouble surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "sumByDouble"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_sumByDouble")
            #expect(sema.symbols.annotations(for: memberSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" }, "Iterable.sumByDouble should carry Deprecated metadata")

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.sumByDouble selector parameter to be a function"); return
            }
            #expect(selectorType.params.count == 1)
            #expect(signature.returnType == sema.types.doubleType)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            #expect(callLinks.filter { $0 == "kk_list_sumByDouble" }.count == 2)
        }
    }

    @Test
    func testIterableFirstNotNullOfResolvesInCallExpressions() throws {
        let source = """
        fun pickLabel(values: Iterable<Int>): String {
            return values.firstNotNullOf<String> { value ->
                if (value == 2) "two" else null
            }
        }

        fun pickListLabel(values: List<Int>): String {
            return values.firstNotNullOf<String> { value ->
                if (value == 3) "three" else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.firstNotNullOf surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "firstNotNullOf"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(links.contains("kk_iterable_firstNotNullOf"))
        }
    }

    @Test
    func testIterableFirstNotNullOfOrNullResolvesInCallExpressions() throws {
        let source = """
        fun pickLabel(values: Iterable<Int>): String? {
            return values.firstNotNullOfOrNull<String> { value ->
                if (value == 2) "two" else null
            }
        }

        fun pickListLabel(values: List<Int>): String? {
            return values.firstNotNullOfOrNull<String> { value ->
                if (value == 3) "three" else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.firstNotNullOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "firstNotNullOfOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(links.contains("kk_iterable_firstNotNullOfOrNull"))
        }
    }

    @Test
    func testIterableMinusElementResolvesToListRuntime() throws {
        let source = """
        fun removeValue(values: Iterable<Int>): List<Int> {
            return values.minusElement(2)
        }

        fun removeFromList(values: List<Int>): List<Int> {
            return values.minusElement(element = 3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.minusElement surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "minusElement"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_minus_element")

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
            else {
                Issue.record("Expected Iterable.minusElement to return List<E>"); return
            }
            #expect(ctx.interner.resolve(returnSymbol.name) == "List")

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            #expect(callLinks.filter { $0 == "kk_list_minus_element" }.count == 2)
        }
    }

    @Test
    func testIterableReduceRightIndexedResolvesToListRuntime() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Int {
            return values.reduceRightIndexed { index, value, acc ->
                index * 100 + value * 10 + acc
            }
        }

        fun checksumFromList(values: List<Int>): Int {
            return values.reduceRightIndexed(operation = { index, value, acc ->
                index + value + acc
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.reduceRightIndexed surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightIndexed"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_reduceRightIndexed")

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.reduceRightIndexed operation parameter to be a function"); return
            }
            #expect(operationType.params.count == 3)
            guard case let .primitive(indexPrimitive, indexNullability) = sema.types.kind(of: operationType.params[0]) else {
                Issue.record("Expected first reduceRightIndexed lambda parameter to be Int"); return
            }
            #expect(indexPrimitive == .int)
            #expect(indexNullability == .nonNull)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // List.reduceRightIndexed is now source-backed; only the Iterable
            // call resolves to the retained runtime bridge.
            #expect(callLinks.filter { $0 == "kk_list_reduceRightIndexed" }.count == 1)
        }
    }

    @Test
    func testIterableReduceRightIndexedOrNullResolvesToListRuntime() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Int? {
            return values.reduceRightIndexedOrNull { index, value, acc ->
                index * 100 + value * 10 + acc
            }
        }

        fun checksumFromList(values: List<Int>): Int? {
            return values.reduceRightIndexedOrNull(operation = { index, value, acc ->
                index + value + acc
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.reduceRightIndexedOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightIndexedOrNull"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_reduceRightIndexedOrNull")

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.reduceRightIndexedOrNull operation parameter to be a function"); return
            }
            #expect(operationType.params.count == 3)
            guard case let .primitive(indexPrimitive, indexNullability) = sema.types.kind(of: operationType.params[0]) else {
                Issue.record("Expected first reduceRightIndexedOrNull lambda parameter to be Int"); return
            }
            #expect(indexPrimitive == .int)
            #expect(indexNullability == .nonNull)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // List.reduceRightIndexedOrNull is now source-backed; only the Iterable
            // call resolves to the retained runtime bridge.
            #expect(callLinks.filter { $0 == "kk_list_reduceRightIndexedOrNull" }.count == 1)
        }
    }

    @Test
    func testIterableReduceRightOrNullResolvesToListRuntime() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Int? {
            return values.reduceRightOrNull { value, acc ->
                value * 10 + acc
            }
        }

        fun checksumFromList(values: List<Int>): Int? {
            return values.reduceRightOrNull(operation = { value, acc ->
                value + acc
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.reduceRightOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightOrNull"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_reduceRightOrNull")

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.reduceRightOrNull operation parameter to be a function"); return
            }
            #expect(operationType.params.count == 2)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // List.reduceRightOrNull is now source-backed; only the Iterable
            // call resolves to the retained runtime bridge.
            #expect(callLinks.filter { $0 == "kk_list_reduceRightOrNull" }.count == 1)
        }
    }

    @Test
    func testListFirstAndOrNullTerminalsReturnElementsWithoutCollectionMarking() throws {
        let source = """
        fun probe(values: List<Int>) {
            values.first()
            values.firstOrNull()
            values.firstOrNull { it > 1 }
            values.lastOrNull()
            values.lastOrNull { it < 3 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let nullableIntType = sema.types.makeNullable(sema.types.intType)
            let expectedTerminalCalls: [(memberName: String, expectedType: TypeID)] = [
                ("first", sema.types.intType),
                ("firstOrNull", nullableIntType),
                ("lastOrNull", nullableIntType),
            ]

            for (memberName, expectedType) in expectedTerminalCalls {
                // Use lastExprID rather than firstExprID: bundled stdlib sources
                // (injected before the fixture's own source) may already contain
                // calls to the same member name, which would otherwise shadow the
                // fixture's own call site.
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && args.isEmpty
                })

                #expect(sema.bindings.exprTypes[callExpr] == expectedType, "Expected \(memberName) to return the expected element type")
                #expect(!(sema.bindings.isCollectionExpr(callExpr)), "Expected \(memberName) result to avoid collection-expression marking")
            }

            for memberName in ["firstOrNull", "lastOrNull"] {
                let predicateCall = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && args.count == 1
                })
                guard case let .memberCall(_, _, _, args, _) = ast.arena.expr(predicateCall),
                      let predicateArg = args.first?.expr
                else {
                    Issue.record("Expected \(memberName)(predicate) call to keep its lambda argument")
                    continue
                }
                #expect(!sema.bindings.isCollectionHOFLambdaExpr(predicateArg), "Expected \(memberName)(predicate) lambda to be unmarked for source-backed lowering")
                #expect(sema.bindings.exprTypes[predicateCall] == nullableIntType, "Expected \(memberName)(predicate) to return nullable element type")
                #expect(!(sema.bindings.isCollectionExpr(predicateCall)), "Expected \(memberName)(predicate) result to avoid collection-expression marking")
            }
        }
    }

    @Test
    func testListMaxOrNullAndMinOrNullRequireComparableElements() throws {
        let source = """
        class Box

        fun render(values: List<Box>) {
            values.maxOrNull()
            values.minOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let boundDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-BOUND" }
            #expect(boundDiagnostics.count == 2, "Expected bound diagnostics for maxOrNull/minOrNull")
        }
    }

    @Test
    func testComparableSyntheticStubUsesContravariantTypeParameter() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let comparableSymbol = try #require(sema.types.comparableInterfaceSymbol)
            #expect(sema.types.nominalTypeParameterVariances(for: comparableSymbol) == [.in], "Expected Comparable to be declared as Comparable<in T>")

            let comparableAny = sema.types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.invariant(sema.types.anyType)],
                nullability: .nonNull
            )))
            let comparableString = sema.types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.invariant(sema.types.stringType)],
                nullability: .nonNull
            )))

            #expect(sema.types.isSubtype(comparableAny, comparableString), "Expected Comparable<Any> to be a subtype of Comparable<String>")
            #expect(!(sema.types.isSubtype(comparableString, comparableAny)), "Expected Comparable<String> not to be a subtype of Comparable<Any>")
        }
    }

    @Test
    func testCollectionFallbackRejectsListOnlyIndexedLookupsOnAbstractCollection() throws {
        let source = """
        fun firstValue(values: Collection<Int>): Int? = values.firstOrNull()
        fun lastValue(values: Collection<Int>): Int? = values.lastOrNull()
        fun fallbackValue(values: Collection<Int>): Int = values.getOrElse(0) { -1 }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in ["firstOrNull", "lastOrNull", "getOrElse"] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil, "Expected Collection.\(memberName) to remain unresolved")
            }

            #expect(!(ctx.diagnostics.diagnostics.isEmpty), "Expected diagnostics for Collection indexed lookup fallbacks")
        }
    }

    @Test
    func testCollectionLastInfersElementType() throws {
        let source = """
        fun lastValue(values: Collection<Int>): Int = values.last()
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
                guard ctx.interner.resolve(callee) == "last" else { return false }
                // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                // List<String>.last() internally; exclude bundled call sites
                // so this finds the user's Collection<Int>.last() call.
                return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            })
            let type = try #require(sema.bindings.exprType(for: callExpr))
            #expect(sema.types.kind(of: type) == .primitive(.int, .nonNull))
        }
    }

    @Test
    func testPrimitiveIteratorSurfacesAreRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let iteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterator")]))
            let specs: [(className: String, nextName: String, elementType: TypeID)] = [
                ("BooleanIterator", "nextBoolean", sema.types.booleanType),
                ("ByteIterator", "nextByte", sema.types.intType),
                ("ShortIterator", "nextShort", sema.types.intType),
                ("IntIterator", "nextInt", sema.types.intType),
                ("LongIterator", "nextLong", sema.types.longType),
                ("FloatIterator", "nextFloat", sema.types.floatType),
                ("DoubleIterator", "nextDouble", sema.types.doubleType),
                ("CharIterator", "nextChar", sema.types.charType),
            ]

            for spec in specs {
                let classFQName = collectionsPkg + [ctx.interner.intern(spec.className)]
                let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
                let classInfo = try #require(sema.symbols.symbol(classSymbol))
                #expect(classInfo.kind == .class)
                #expect(classInfo.flags.contains(.synthetic))
                #expect(classInfo.flags.contains(.abstractType))
                #expect(sema.symbols.directSupertypes(for: classSymbol).contains(iteratorSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: classSymbol, supertype: iteratorSymbol) == [.out(spec.elementType)])

                let primitiveNextSymbol = try #require(sema.symbols.lookup(fqName: classFQName + [ctx.interner.intern(spec.nextName)]))
                let primitiveNextInfo = try #require(sema.symbols.symbol(primitiveNextSymbol))
                #expect(primitiveNextInfo.flags.isSuperset(of: [.synthetic, .abstractType]))
                let primitiveNextSignature = try #require(sema.symbols.functionSignature(for: primitiveNextSymbol))
                #expect(primitiveNextSignature.parameterTypes.isEmpty)
                #expect(primitiveNextSignature.returnType == spec.elementType)

                let nextSymbol = try #require(sema.symbols.lookup(fqName: classFQName + [ctx.interner.intern("next")]))
                let nextInfo = try #require(sema.symbols.symbol(nextSymbol))
                #expect(nextInfo.flags.isSuperset(of: [.synthetic, .openType, .overrideMember, .operatorFunction]))
                #expect(try #require(sema.symbols.functionSignature(for: nextSymbol)).returnType == spec.elementType)
            }
        }
    }

    @Test
    func testPrimitiveIteratorSubclassResolvesAsIterator() throws {
        let source = """
        import kotlin.collections.IntIterator
        import kotlin.collections.Iterator

        class ProbeIntIterator : IntIterator() {
            override fun hasNext(): Boolean = false
            override fun nextInt(): Int = 42
        }

        fun accept(iterator: Iterator<Int>) {}

        fun probe(iterator: ProbeIntIterator): Int {
            accept(iterator)
            return iterator.nextInt() + iterator.next()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected primitive iterator subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractIteratorSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let abstractIteratorFQName = ["kotlin", "collections", "AbstractIterator"]
                .map { ctx.interner.intern($0) }
            let abstractIteratorSymbol = try #require(sema.symbols.lookup(fqName: abstractIteratorFQName))
            let abstractIteratorInfo = try #require(sema.symbols.symbol(abstractIteratorSymbol))
            #expect(abstractIteratorInfo.kind == .class)
            #expect(abstractIteratorInfo.flags.contains(.synthetic))
            #expect(abstractIteratorInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractIteratorSymbol) == [.invariant])

            let iteratorSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterator"].map { ctx.interner.intern($0) }))
            #expect(sema.symbols.directSupertypes(for: abstractIteratorSymbol).contains(iteratorSymbol))
            #expect(sema.types.directNominalSupertypes(for: abstractIteratorSymbol).contains(iteratorSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractIteratorSymbol, supertype: iteratorSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractIteratorSymbol, supertype: iteratorSymbol).count == 1)

            let expectedMembers: [(name: String, visibility: Visibility, requiredFlags: SymbolFlags, parameterCount: Int)] = [
                ("computeNext", .protected, [.synthetic, .abstractType], 0),
                ("done", .protected, [.synthetic], 0),
                ("setNext", .protected, [.synthetic], 1),
                ("hasNext", .public, [.synthetic, .openType, .overrideMember, .operatorFunction], 0),
                ("next", .public, [.synthetic, .openType, .overrideMember, .operatorFunction], 0),
            ]
            for expected in expectedMembers {
                let memberSymbol = try #require(sema.symbols.lookup(fqName: abstractIteratorFQName + [ctx.interner.intern(expected.name)]))
                let memberInfo = try #require(sema.symbols.symbol(memberSymbol))
                #expect(memberInfo.visibility == expected.visibility)
                #expect(memberInfo.flags.isSuperset(of: expected.requiredFlags))
                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == expected.parameterCount)
            }
        }
    }

    @Test
    func testAbstractIteratorSubclassProtectedMembersResolve() throws {
        let source = """
        import kotlin.collections.AbstractIterator
        import kotlin.collections.Iterator

        class OneShotIterator(private val value: Int) : AbstractIterator<Int>() {
            override fun computeNext() {
                setNext(value)
                done()
            }
        }

        fun accept(iterator: Iterator<Int>) {}

        fun probe(iterator: OneShotIterator) {
            accept(iterator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractIterator subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractCollectionSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let abstractCollectionFQName = ["kotlin", "collections", "AbstractCollection"]
                .map { ctx.interner.intern($0) }
            let abstractCollectionSymbol = try #require(sema.symbols.lookup(fqName: abstractCollectionFQName))
            let abstractCollectionInfo = try #require(sema.symbols.symbol(abstractCollectionSymbol))
            #expect(abstractCollectionInfo.kind == .class)
            #expect(abstractCollectionInfo.flags.contains(.synthetic))
            #expect(abstractCollectionInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractCollectionSymbol) == [.out])

            let collectionSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Collection"].map { ctx.interner.intern($0) }))
            #expect(sema.symbols.directSupertypes(for: abstractCollectionSymbol).contains(collectionSymbol))
            #expect(sema.types.directNominalSupertypes(for: abstractCollectionSymbol).contains(collectionSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractCollectionSymbol, supertype: collectionSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractCollectionSymbol, supertype: collectionSymbol).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractCollectionFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            let signature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
            #expect(signature.parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractCollectionCanBeUsedAsCollectionSupertype() throws {
        let source = """
        import kotlin.collections.AbstractCollection
        import kotlin.collections.Collection

        abstract class ProbeCollection : AbstractCollection<Int>()

        fun accept(values: Collection<Int>) {}

        fun probe(values: ProbeCollection) {
            accept(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractCollection subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractListSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let abstractCollectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")]))
            let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("List")]))

            let abstractListFQName = collectionsPkg + [ctx.interner.intern("AbstractList")]
            let abstractListSymbol = try #require(sema.symbols.lookup(fqName: abstractListFQName))
            let abstractListInfo = try #require(sema.symbols.symbol(abstractListSymbol))
            #expect(abstractListInfo.kind == .class)
            #expect(abstractListInfo.flags.contains(.synthetic))
            #expect(abstractListInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractListSymbol) == [.out])

            let directSupertypes = sema.symbols.directSupertypes(for: abstractListSymbol)
            #expect(directSupertypes.contains(abstractCollectionSymbol))
            #expect(directSupertypes.contains(listSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractListSymbol, supertype: abstractCollectionSymbol).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: abstractListSymbol, supertype: listSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractListSymbol, supertype: abstractCollectionSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractListSymbol, supertype: listSymbol).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractListFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractSetSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Collection")]))
            let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")]))

            let abstractSetFQName = collectionsPkg + [ctx.interner.intern("AbstractSet")]
            let abstractSetSymbol = try #require(sema.symbols.lookup(fqName: abstractSetFQName))
            let abstractSetInfo = try #require(sema.symbols.symbol(abstractSetSymbol))
            #expect(abstractSetInfo.kind == .class)
            #expect(abstractSetInfo.flags.contains(.synthetic))
            #expect(abstractSetInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractSetSymbol) == [.out])

            let abstractCollectionSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")]
            )
            let collectionSupertype = abstractCollectionSymbol ?? collectionSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractSetSymbol)
            #expect(directSupertypes.contains(collectionSupertype))
            #expect(directSupertypes.contains(setSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractSetSymbol, supertype: collectionSupertype).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: abstractSetSymbol, supertype: setSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractSetSymbol, supertype: collectionSupertype).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractSetSymbol, supertype: setSymbol).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractSetFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractListCanBeUsedAsListSupertype() throws {
        let source = """
        import kotlin.collections.AbstractList
        import kotlin.collections.Collection
        import kotlin.collections.List

        abstract class ProbeList : AbstractList<Int>()

        fun acceptCollection(values: Collection<Int>) {}
        fun acceptList(values: List<Int>) {}

        fun probe(values: ProbeList) {
            acceptCollection(values)
            acceptList(values)
            values[0]
            values.listIterator()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractList subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractSetCanBeUsedAsCollectionAndSetSupertype() throws {
        let source = """
        import kotlin.collections.AbstractSet
        import kotlin.collections.Collection
        import kotlin.collections.Set

        abstract class ProbeSet : AbstractSet<Int>()

        fun acceptCollection(values: Collection<Int>) {}
        fun acceptSet(values: Set<Int>) {}

        fun probe(values: ProbeSet) {
            acceptCollection(values)
            acceptSet(values)
            values.contains(1)
            values.isEmpty()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractSet subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testRandomAccessMarkerInterfaceSurfaceIsRegistered() throws {
        let source = """
        import kotlin.collections.RandomAccess

        class IndexedBag : RandomAccess

        fun keepRandomAccess(marker: RandomAccess): RandomAccess {
            return marker
        }

        fun probe(value: IndexedBag): RandomAccess {
            return keepRandomAccess(value)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected RandomAccess marker interface surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let sema = try #require(ctx.sema)
            let randomAccessFQName = ["kotlin", "collections", "RandomAccess"]
                .map { ctx.interner.intern($0) }
            let randomAccessSymbol = try #require(sema.symbols.lookup(fqName: randomAccessFQName))
            let randomAccessInfo = try #require(sema.symbols.symbol(randomAccessSymbol))
            #expect(randomAccessInfo.kind == .interface)
            #expect(randomAccessInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterSymbols(for: randomAccessSymbol).isEmpty)
        }
    }

    @Test
    func testAbstractMutableCollectionSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Collection")]))
            let mutableCollectionFQName = collectionsPkg + [ctx.interner.intern("MutableCollection")]
            let mutableCollectionSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableCollectionSymbol) == [.invariant])
            #expect(sema.symbols.directSupertypes(for: mutableCollectionSymbol).contains(collectionSymbol))
            #expect(sema.types.directNominalSupertypes(for: mutableCollectionSymbol).contains(collectionSymbol))

            let expectedMutableMembers: [(name: String, parameterCount: Int)] = [
                ("add", 1),
                ("addAll", 1),
                ("clear", 0),
                ("remove", 1),
                ("removeAll", 1),
                ("retainAll", 1),
            ]
            for expected in expectedMutableMembers {
                let memberSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [ctx.interner.intern(expected.name)]))
                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == expected.parameterCount)
            }

            let addSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [ctx.interner.intern("add")]))
            #expect(sema.symbols.externalLinkName(for: addSymbol) == "kk_mutable_collection_add")
            let addAllSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [ctx.interner.intern("addAll")]))
            #expect(sema.symbols.externalLinkName(for: addAllSymbol) == "kk_mutable_collection_addAll")

            let abstractMutableCollectionFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableCollection")]
            let abstractMutableCollectionSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableCollectionFQName))
            let abstractMutableCollectionInfo = try #require(sema.symbols.symbol(abstractMutableCollectionSymbol))
            #expect(abstractMutableCollectionInfo.kind == .class)
            #expect(abstractMutableCollectionInfo.flags.contains(.synthetic))
            #expect(abstractMutableCollectionInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableCollectionSymbol) == [.invariant])

            let abstractCollectionSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")]
            )
            let readonlySupertype = abstractCollectionSymbol ?? collectionSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableCollectionSymbol)
            #expect(directSupertypes.contains(readonlySupertype))
            #expect(directSupertypes.contains(mutableCollectionSymbol))
            #expect(sema.symbols.supertypeTypeArgs(
                    for: abstractMutableCollectionSymbol,
                    supertype: readonlySupertype
                ).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(
                    for: abstractMutableCollectionSymbol,
                    supertype: mutableCollectionSymbol
                ).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableCollectionFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractMutableCollectionCanBeUsedAsMutableCollectionSupertype() throws {
        let source = """
        import kotlin.collections.AbstractMutableCollection
        import kotlin.collections.Collection
        import kotlin.collections.MutableCollection

        abstract class ProbeMutableCollection : AbstractMutableCollection<Int>()

        fun acceptReadonly(values: Collection<Int>) {}
        fun acceptMutable(values: MutableCollection<Int>) {}

        fun probe(values: ProbeMutableCollection) {
            acceptReadonly(values)
            acceptMutable(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractMutableCollection subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractMutableSetSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")]))
            let mutableSetSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableSet")]))
            let abstractMutableSetFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableSet")]
            let abstractMutableSetSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableSetFQName))
            let abstractMutableSetInfo = try #require(sema.symbols.symbol(abstractMutableSetSymbol))
            #expect(abstractMutableSetInfo.kind == .class)
            #expect(abstractMutableSetInfo.flags.contains(.synthetic))
            #expect(abstractMutableSetInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableSetSymbol) == [.invariant])

            let abstractSetSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractSet")]
            )
            let readonlySupertype = abstractSetSymbol ?? setSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableSetSymbol)
            #expect(directSupertypes.contains(readonlySupertype))
            #expect(directSupertypes.contains(mutableSetSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableSetSymbol, supertype: readonlySupertype).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableSetSymbol, supertype: mutableSetSymbol).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableSetFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractMutableMapSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let mapSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Map")]))
            let mutableMapSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableMap")]))
            let abstractMutableMapFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableMap")]
            let abstractMutableMapSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableMapFQName))
            let abstractMutableMapInfo = try #require(sema.symbols.symbol(abstractMutableMapSymbol))
            #expect(abstractMutableMapInfo.kind == .class)
            #expect(abstractMutableMapInfo.flags.contains(.synthetic))
            #expect(abstractMutableMapInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableMapSymbol) == [.invariant, .invariant])

            let abstractMapSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractMap")]
            )
            let readonlySupertype = abstractMapSymbol ?? mapSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableMapSymbol)
            #expect(directSupertypes.contains(readonlySupertype))
            #expect(directSupertypes.contains(mutableMapSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableMapSymbol, supertype: readonlySupertype).count == 2)
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableMapSymbol, supertype: mutableMapSymbol).count == 2)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableMapFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractMutableSetCanBeUsedAsSetAndMutableSetSupertype() throws {
        let source = """
        import kotlin.collections.AbstractMutableSet
        import kotlin.collections.Set
        import kotlin.collections.MutableSet

        class ProbeMutableSet : AbstractMutableSet<Int>()

        fun acceptReadonly(values: Set<Int>) {}
        fun acceptMutable(values: MutableSet<Int>) {}

        fun probe(values: ProbeMutableSet) {
            acceptReadonly(values)
            acceptMutable(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractMutableSet subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractMutableMapCanBeUsedAsMapAndMutableMapSupertype() throws {
        let source = """
        import kotlin.collections.AbstractMutableMap
        import kotlin.collections.Map
        import kotlin.collections.MutableMap

        class ProbeMutableMap : AbstractMutableMap<String, Int>()

        fun acceptReadonly(values: Map<String, Int>) {}
        fun acceptMutable(values: MutableMap<String, Int>) {}

        fun probe(values: ProbeMutableMap) {
            acceptReadonly(values)
            acceptMutable(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractMutableMap subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testMutableListIteratorSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let listIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("ListIterator")]))
            let mutableIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator")]))

            let mutableListIteratorFQName = collectionsPkg + [ctx.interner.intern("MutableListIterator")]
            let mutableListIteratorSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName))
            let mutableListIteratorInfo = try #require(sema.symbols.symbol(mutableListIteratorSymbol))
            #expect(mutableListIteratorInfo.kind == .interface)
            #expect(mutableListIteratorInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableListIteratorSymbol) == [.invariant])

            let directSupertypes = sema.symbols.directSupertypes(for: mutableListIteratorSymbol)
            #expect(directSupertypes.contains(listIteratorSymbol))
            #expect(directSupertypes.contains(mutableIteratorSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: mutableListIteratorSymbol, supertype: listIteratorSymbol).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: mutableListIteratorSymbol, supertype: mutableIteratorSymbol).count == 1)

            for memberName in ["add", "set"] {
                let memberSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName + [ctx.interner.intern(memberName)]))
                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == 1)
                #expect(signature.returnType == sema.types.unitType)
            }
            let removeSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName + [ctx.interner.intern("remove")]))
            let removeSignature = try #require(sema.symbols.functionSignature(for: removeSymbol))
            #expect(removeSignature.parameterTypes.isEmpty)
            #expect(removeSignature.returnType == sema.types.unitType)

            let mutableListSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableList")]))
            let listIteratorMember = try #require(sema.symbols.lookup(
                    fqName: collectionsPkg + [ctx.interner.intern("MutableList"), ctx.interner.intern("listIterator")]
                ))
            #expect(sema.symbols.parentSymbol(for: listIteratorMember) == mutableListSymbol)
            let listIteratorSignature = try #require(sema.symbols.functionSignature(for: listIteratorMember))
            guard case let .classType(returnType) = sema.types.kind(of: listIteratorSignature.returnType) else {
                Issue.record("MutableList.listIterator should return MutableListIterator<E>")
                return
            }
            #expect(returnType.classSymbol == mutableListIteratorSymbol)
        }
    }

    @Test
    func testMutableIterableSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let iterableSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterable")]))
            let iteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterator")]))
            let mutableIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator")]))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableIteratorSymbol) == [.out])
            #expect(sema.symbols.directSupertypes(for: mutableIteratorSymbol).contains(iteratorSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: mutableIteratorSymbol, supertype: iteratorSymbol).count == 1)
            let removeSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator"), ctx.interner.intern("remove")]))
            let removeSignature = try #require(sema.symbols.functionSignature(for: removeSymbol))
            #expect(removeSignature.parameterTypes.isEmpty)
            #expect(removeSignature.returnType == sema.types.unitType)

            let mutableIterableFQName = collectionsPkg + [ctx.interner.intern("MutableIterable")]
            let mutableIterableSymbol = try #require(sema.symbols.lookup(fqName: mutableIterableFQName))
            let mutableIterableInfo = try #require(sema.symbols.symbol(mutableIterableSymbol))
            #expect(mutableIterableInfo.kind == .interface)
            #expect(mutableIterableInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableIterableSymbol) == [.out])
            #expect(sema.symbols.directSupertypes(for: mutableIterableSymbol).contains(iterableSymbol))
            #expect(sema.types.directNominalSupertypes(for: mutableIterableSymbol).contains(iterableSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: mutableIterableSymbol, supertype: iterableSymbol).count == 1)

            let iteratorMember = try #require(sema.symbols.lookup(fqName: mutableIterableFQName + [ctx.interner.intern("iterator")]))
            #expect(try #require(sema.symbols.symbol(iteratorMember)).flags.contains(.operatorFunction))
            let iteratorSignature = try #require(sema.symbols.functionSignature(for: iteratorMember))
            #expect(iteratorSignature.parameterTypes.isEmpty)
            guard case let .classType(iteratorReturnType) = sema.types.kind(of: iteratorSignature.returnType) else {
                Issue.record("MutableIterable.iterator should return MutableIterator<T>")
                return
            }
            #expect(iteratorReturnType.classSymbol == mutableIteratorSymbol)

            for collectionName in ["MutableList", "MutableSet"] {
                let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern(collectionName)]))
                #expect(sema.symbols.directSupertypes(for: collectionSymbol).contains(mutableIterableSymbol))
                #expect(sema.types.directNominalSupertypes(for: collectionSymbol).contains(mutableIterableSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: collectionSymbol, supertype: mutableIterableSymbol).count == 1)
            }
        }
    }

    @Test
    func testMutableListIteratorMembersResolveFromMutableList() throws {
        let source = """
        fun probe(values: MutableList<Int>) {
            val iterator = values.listIterator()
            iterator.add(1)
            iterator.set(2)
            iterator.remove()
            iterator.hasPrevious()
            iterator.previous()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected MutableListIterator surface to resolve from MutableList: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testMutableIterableSubtypeResolution() throws {
        let source = """
        import kotlin.collections.Iterable
        import kotlin.collections.MutableIterable
        import kotlin.collections.MutableList
        import kotlin.collections.MutableSet

        abstract class ProbeMutableIterable : MutableIterable<Int>

        fun acceptIterable(values: Iterable<Int>) {}
        fun acceptMutableIterable(values: MutableIterable<Int>) {}

        fun probeIterable(values: ProbeMutableIterable) {
            acceptIterable(values)
            acceptMutableIterable(values)
            values.iterator().remove()
        }

        fun probeList(values: MutableList<Int>) {
            acceptMutableIterable(values)
        }

        fun probeSet(values: MutableSet<Int>) {
            acceptMutableIterable(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected MutableIterable subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testSetFallbackRejectsListOnlyIndexedLookups() throws {
        let source = """
        fun firstValue(values: Set<Int>): Int? = values.firstOrNull()
        fun lastValue(values: Set<Int>): Int? = values.lastOrNull()
        fun fallbackValue(values: Set<Int>): Int = values.getOrElse(0) { -1 }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in ["firstOrNull", "lastOrNull", "getOrElse"] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil, "Expected Set.\(memberName) to remain unresolved")
            }

            #expect(!(ctx.diagnostics.diagnostics.isEmpty), "Expected diagnostics for Set indexed lookup fallbacks")
        }
    }

    @Test
    func testCollectionFallbackResolvesTrailingLambdaIndexedLookups() throws {
        let source = """
        fun probe(): Int {
            val list = listOf(1, 2, 3)
            val listValue = list.getOrElse(5) { -1 }
            val map = mapOf("a" to 1, "b" to 2)
            val mapValue = map.getOrElse("z") { 99 }
            val mutableMap = mutableMapOf("a" to 1, "b" to 2)
            val mutableValue = mutableMap.getOrPut("c") { 3 }
            return listValue + mapValue + mutableValue
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let listCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrElse",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "list"
            })
            let listCallee = try #require(sema.bindings.callBinding(for: listCall)?.chosenCallee)
            let listSymbol = try #require(sema.symbols.symbol(listCallee))
            #expect(sema.symbols.externalLinkName(for: listCallee) == nil)
            #expect(!listSymbol.flags.contains(.synthetic))
            #expect(ctx.interner.resolve(listSymbol.name) == "getOrElse")

            let mapCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrElse",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "map"
            })
            let mapCallee = try #require(sema.bindings.callBinding(for: mapCall)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: mapCallee) == "kk_map_getOrElse")

            let mutableCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrPut",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "mutableMap"
            })
            let mutableCallee = try #require(sema.bindings.callBinding(for: mutableCall)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: mutableCallee) == "kk_mutable_map_getOrPut")
        }
    }

    @Test
    func testMapGetOrElseAssignsLambdaExpectedTypeToLambdaArgument() throws {
        let source = """
        fun useMapDefault(values: Map<String, Int>): Int {
            return values.getOrElse("z") { 99 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "getOrElse"
                })
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType, "Expected getOrElse result to be Int")
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected map getOrElse fallback to resolve without diagnostics, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testListBinarySearchHasComparableElementUpperBound() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookupAll(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("List"),
                        ctx.interner.intern("binarySearch"),
                    ]
                ).first(where: { sema.symbols.externalLinkName(for: $0) == "kk_list_binarySearch" }))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.typeParameterUpperBoundsList.count == 1)
            let upperBounds = signature.typeParameterUpperBoundsList[0]
            #expect(upperBounds.count == 1, "Expected Comparable upper bound for binarySearch element type")

            guard case let .classType(boundType) = sema.types.kind(of: upperBounds[0]) else {
                Issue.record("Expected binarySearch upper bound to be a class type"); return
            }

            #expect(boundType.classSymbol == sema.types.comparableInterfaceSymbol)
            #expect(boundType.args.count == 1)

            guard case let .invariant(argumentType) = boundType.args[0] else {
                Issue.record("Expected Comparable upper bound to reference invariant element type"); return
            }

            let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            )))
            #expect(argumentType == expectedElementType)
        }
    }

    @Test
    func testListBinarySearchComparatorOverloadHasDefaultedRange() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let listSymbol = try #require(sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern("List"),
                ]))
            let symbolID = try #require(sema.symbols.lookupByShortName(ctx.interner.intern("binarySearch")).first(where: { candidate in
                    sema.symbols.parentSymbol(for: candidate) == listSymbol
                        && sema.symbols.externalLinkName(for: candidate) == "kk_list_binarySearch_comparator"
                }))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.parameterTypes.count == 4)
            #expect(signature.valueParameterSymbols.count == 4)
            #expect(signature.valueParameterHasDefaultValues == [false, false, true, true])
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.classTypeParameterCount == 1)
            #expect(signature.typeParameterUpperBoundsList.isEmpty)

            let parameterNames = signature.valueParameterSymbols.compactMap { paramSymbol in
                sema.symbols.symbol(paramSymbol)?.name
            }.map { ctx.interner.resolve($0) }
            #expect(parameterNames == ["element", "comparator", "fromIndex", "toIndex"])

            #expect(signature.parameterTypes[0] == sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            ))))
            #expect(signature.parameterTypes[2] == sema.types.intType)
            #expect(signature.parameterTypes[3] == sema.types.intType)

            if let comparatorSymbol = sema.symbols.lookupByShortName(ctx.interner.intern("Comparator")).first,
               case let .classType(comparatorClassType) = sema.types.kind(of: signature.parameterTypes[1])
            {
                #expect(comparatorClassType.classSymbol == comparatorSymbol)
                #expect(comparatorClassType.args.count == 1)
            } else {
                guard case let .functionType(comparatorFunctionType) = sema.types.kind(of: signature.parameterTypes[1]) else {
                    Issue.record("Expected binarySearch comparator parameter to be Comparator<T> or a comparator function type"); return
                }
                #expect(comparatorFunctionType.params.count == 2)
                #expect(comparatorFunctionType.returnType == sema.types.intType)
            }
        }
    }

    @Test
    func testListBinarySearchByUsesComparableKeyAndRuntimeOverloads() throws {
        let source = """
        data class Person(val name: String, val age: Int)

        fun render(values: List<Person>) {
            values.binarySearchBy(35) { it.age }
            values.binarySearchBy(35, 1) { it.age }
            values.binarySearchBy(35, 1, 4) { it.age }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedOverloads: [(externalLinkName: String, parameterCount: Int)] = [
                ("kk_list_binarySearchBy", 2),
                ("kk_list_binarySearchBy_fromIndex", 3),
                ("kk_list_binarySearchBy_range", 4),
            ]

            let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "binarySearchBy"
                else {
                    return nil
                }
                return exprID
            }
            #expect(callExprIDs.count == expectedOverloads.count, "Expected three binarySearchBy calls")

            for (index, callExprID) in callExprIDs.enumerated() {
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExprID)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedOverloads[index].externalLinkName, "Expected binarySearchBy overload \(index) to resolve to \(expectedOverloads[index].externalLinkName)")
                #expect(sema.bindings.exprType(for: callExprID) == sema.types.intType, "Expected binarySearchBy overload \(index) to return Int")
            }

            let listFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("binarySearchBy"),
            ]

            for overload in expectedOverloads {
                let symbolID = try #require(sema.symbols.lookupAll(fqName: listFQName).first(where: {
                        sema.symbols.externalLinkName(for: $0) == overload.externalLinkName
                    }))
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.returnType == sema.types.intType)
                #expect(signature.parameterTypes.count == overload.parameterCount)
                #expect(signature.typeParameterSymbols.count == 2)
                #expect(signature.typeParameterUpperBoundsList.count == 2)

                let selectorType = try #require(signature.parameterTypes.last)
                guard case let .functionType(functionType) = sema.types.kind(of: selectorType) else {
                    Issue.record("Expected selector parameter for \(overload.externalLinkName) to be a function type"); return
                }
                #expect(functionType.params.count == 1)

                let expectedListElementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                )))
                #expect(functionType.params[0] == expectedListElementType)
                #expect(functionType.returnType == signature.parameterTypes[0])

                let keyUpperBounds = signature.typeParameterUpperBoundsList[1]
                #expect(keyUpperBounds.count == 1, "Expected Comparable upper bound for \(overload.externalLinkName) key type")
                guard case let .classType(boundType) = sema.types.kind(of: keyUpperBounds[0]) else {
                    Issue.record("Expected \(overload.externalLinkName) upper bound to be a class type"); return
                }
                #expect(boundType.classSymbol == sema.types.comparableInterfaceSymbol)
                #expect(boundType.args.count == 1)

                guard case let .invariant(argumentType) = boundType.args[0] else {
                    Issue.record("Expected \(overload.externalLinkName) upper bound to reference invariant key type"); return
                }

                let expectedKeyType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[1],
                    nullability: .nonNull
                )))
                #expect(argumentType == expectedKeyType)
                #expect(signature.parameterTypes[0] == sema.types.makeNullable(expectedKeyType))

                if overload.parameterCount >= 3 {
                    #expect(signature.parameterTypes[1] == sema.types.intType)
                }
                if overload.parameterCount == 4 {
                    #expect(signature.parameterTypes[2] == sema.types.intType)
                }
            }
        }
    }

    @Test
    func testListToTypeArrayUsesTypedArrayRuntimeExternalLink() throws {
        let source = """
        fun convert(values: List<String>) {
            val converted: Array<String> = values.toTypedArray()
            converted.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toTypedArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toTypedArray")
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            guard case let .classType(classType) = sema.types.kind(of: signature.returnType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toTypedArray to return Array"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "Array")
        }
    }

    @Test
    func testIterableLocalVariableFromNonFactoryFunctionResolvesFilterAndCount() throws {
        // Regression test: assigning the result of an ordinary (non collection-factory)
        // function call to an explicitly `Iterable<T>`-typed local used to leave that
        // local's receiver classification without isCollectionExpr/isCollectionType/
        // isSequenceReceiver, so tryCollectionMemberFallback's guard rejected members
        // like filter/count even though the static receiver type is nominally Iterable.
        let source = """
        fun getStrings(): List<String> = listOf("a", "bb", "ccc")

        fun checksum(): Int {
            val parts = getStrings()
            val iter: Iterable<String> = parts
            val filtered = iter.filter { it.length > 1 }
            return iter.count() + filtered.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable<T> local from a non-factory function call to resolve filter/count cleanly, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let filterExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filter"
            })
            #expect(sema.bindings.callBinding(for: filterExpr)?.chosenCallee != nil, "Expected filter call on the Iterable-typed local to bind to a callee")

            let countExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "count" && args.isEmpty
            })
            #expect(sema.bindings.exprType(for: countExpr) == sema.types.intType)
        }
    }

    @Test
    func testIterableParameterFromNonListLiteralArgumentResolvesFilterAndCount() throws {
        // Companion regression coverage: the same static-type gap also affected
        // Iterable<T>-typed function parameters (not just locals), since parameters
        // never carry the isCollectionExpr propagation mark either.
        let source = """
        fun checksum(values: Iterable<Int>): Int {
            return values.filter { it > 1 }.count()
        }

        fun caller(): Int = checksum(listOf(1, 2, 3))
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable<T> parameter to resolve filter/count cleanly, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")
        }
    }

}

struct SyntheticMemberCallCase {
    let source: String
    let memberName: String
    let expectedExternalLink: String
    let expectedTypeShape: SyntheticMemberTypeShape?
}

enum SyntheticMemberTypeShape {
    case classNamed(String)
}

func assertSyntheticMemberCall(
    _ testCase: SyntheticMemberCallCase,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try withTemporaryFile(contents: testCase.source) { path in
        let ctx = makeCompilationContext(inputs: [path])
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected \(testCase.memberName) to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        // Use lastExprID rather than firstExprID: bundled stdlib sources (injected
        // before the fixture's own source) may contain unrelated calls to the same
        // member name (e.g. Sequence aggregate HOFs calling `this.toList()`
        // internally), which would otherwise shadow the fixture's own call site.
        let callExpr = try #require(lastExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == testCase.memberName
        })
        let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == testCase.expectedExternalLink, "Expected \(testCase.memberName) to resolve to \(testCase.expectedExternalLink)")

        if let expectedTypeShape = testCase.expectedTypeShape {
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            try assertSyntheticMemberType(
                resultType,
                matches: expectedTypeShape,
                sema: sema,
                interner: ctx.interner,
                memberName: testCase.memberName,
                file: file,
                line: line
            )
        }
    }
}

func assertSyntheticMemberType(
    _ type: TypeID,
    matches expectedTypeShape: SyntheticMemberTypeShape,
    sema: SemaModule,
    interner: StringInterner,
    memberName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    switch expectedTypeShape {
    case let .classNamed(expectedName):
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            Issue.record("Expected \(memberName) to return \(expectedName)"); return
        }
        #expect(interner.resolve(symbol.name) == expectedName)
    }
}

func projectedType(
    _ arg: TypeArg,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> TypeID {
    switch arg {
    case let .invariant(type), let .out(type), let .in(type):
        return type
    case .star:
        return try #require(nil as TypeID?)
    }
}

func assertListType(
    _ type: TypeID,
    elementType expectedElementType: TypeID,
    sema: SemaModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard case let .classType(listType) = sema.types.kind(of: type) else {
        Issue.record("Expected List type"); return
    }
    #expect(try interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
    #expect(listType.args.count == 1)
    let elementType = try projectedType(try #require(listType.args.first), file: file, line: line)
    #expect(elementType == expectedElementType)
}
#endif
