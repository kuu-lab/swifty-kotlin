@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import RuntimeABI
import Testing

@Suite(.serialized)
struct BuildKIRCodegenRegressionTests {
    /// Select operations from the canonical ABI family without copying C link names.
    private func abiFunctions(
        _ operations: [String],
        in family: [RuntimeABIFunctionSpec],
        privateBridge: Bool = false
    ) throws -> [RuntimeABIFunctionSpec] {
        try operations.map { operation in
            let matches = family.filter { function in
                function.name.split(separator: "_").dropFirst().joined(separator: "_") == operation
                    && function.name.hasPrefix("__") == privateBridge
            }
            try #require(matches.count == 1, "Expected one ABI entry for \(operation), got \(matches.map(\.name))")
            return try #require(matches.first)
        }
    }

    private func expectNonThrowingCallees(_ functions: [RuntimeABIFunctionSpec]) {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)
        #expect(!functions.isEmpty)
        for function in functions {
            #expect(!function.isThrowing)
            #expect(callees.contains(interner.intern(function.name)), "Missing \(function.name)")
        }
    }

    private func expectRuntimeCalls(
        _ functions: [RuntimeABIFunctionSpec],
        in body: [KIRInstruction],
        interner: StringInterner
    ) throws {
        let throwFlags = extractThrowFlags(from: body, interner: interner)
        for function in functions {
            let flags = try #require(throwFlags[function.name], "Missing \(function.name)")
            #expect(!flags.isEmpty)
            #expect(flags.allSatisfy { $0 == function.isThrowing }, "Throw flags disagree with ABI for \(function.name)")
        }
    }

    /// Reject undeclared legacy helpers as well as misspelled runtime targets.
    private func expectDeclaredCallees(in body: [KIRInstruction], context ctx: CompilationContext) throws {
        let sema = try #require(ctx.sema)
        var declared = Set(RuntimeABIExterns.allExterns.map { ctx.interner.intern($0.name) })
        let compilerBuiltins = RuntimeABISpec.compilerInternalNonThrowingCalleeNames
            .union(RuntimeABISpec.compilerInternalBuiltinCalleeNames)
        declared.formUnion(compilerBuiltins.map(ctx.interner.intern))
        let module = try #require(ctx.kir)
        declared.formUnion(findAllKIRFunctions(in: module).map(\.name))
        let calledSymbols = Set(body.compactMap { instruction -> SymbolID? in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return nil }
            return symbol
        })
        for symbol in sema.symbols.allSymbols() where symbol.kind == .function {
            declared.insert(symbol.name)
            guard sema.symbols.isSourceBackedSymbol(symbol.id) else { continue }
            let linkName = sema.symbols.externalLinkName(for: symbol.id)
            if let linkName {
                declared.insert(ctx.interner.intern(linkName))
            }
            // Imported default stubs may have link metadata without a Sema/KIR declaration.
            let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: symbol.id)
            if calledSymbols.contains(stubSymbol),
               sema.symbols.functionSignature(for: symbol.id)?.valueParameterHasDefaultValues.contains(true) == true,
               let stubLinkName = sema.symbols.externalLinkName(for: stubSymbol) {
                declared.insert(ctx.interner.intern(stubLinkName))
                declared.insert(ctx.interner.intern(ctx.interner.resolve(symbol.name) + "$default"))
                if let linkName {
                    declared.insert(ctx.interner.intern(linkName + "$default"))
                }
            }
        }
        let unexpected = body.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction,
                  !declared.contains(callee) else { return nil }
            return ctx.interner.resolve(callee)
        }
        #expect(unexpected.isEmpty, "Calls must resolve to a declaration or ABI extern: \(unexpected)")
    }

    private func expectSourceBackedCalls(
        _ names: [String],
        in body: [KIRInstruction],
        context ctx: CompilationContext
    ) throws {
        try expectDeclaredCallees(in: body, context: ctx)
        let sema = try #require(ctx.sema)
        for name in names {
            let expectedName = ctx.interner.intern(name)
            let calls = body.filter { instruction in
                guard case let .call(symbolID?, _, _, _, _, _, _, _) = instruction,
                      let symbol = sema.symbols.symbol(symbolID) else { return false }
                return symbol.name == expectedName
            }
            #expect(!calls.isEmpty, "Missing source-backed call to \(name)")
            for instruction in calls {
                guard case let .call(symbolID?, callee, _, _, _, _, _, _) = instruction else { continue }
                #expect(sema.symbols.isSourceBackedSymbol(symbolID), "\(name) must bind to Kotlin source")
                let expectedCallee = sema.symbols.externalLinkName(for: symbolID).map(ctx.interner.intern) ?? expectedName
                #expect(callee == expectedCallee)
                #expect(RuntimeABIExterns.externDecl(named: ctx.interner.resolve(callee)) == nil)
            }
        }
    }

    private func expectArrayRuntimeCallsThrow(body: [KIRInstruction], interner: StringInterner) throws {
        let functions = try abiFunctions(["array_new_checked", "array_set", "array_get"], in: RuntimeABISpec.arrayFunctions)
        #expect(functions.allSatisfy { $0.isThrowing })
        try expectRuntimeCalls(functions, in: body, interner: interner)
    }

    @Test
    func testBuildKIRLowersListFirstAndOrNullTerminalsToCollectionRuntimeCalls() throws {
        let source = """
        fun main(values: List<Int>) {
            values.first()
            values.firstOrNull()
            values.lastOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["first", "firstOrNull", "lastOrNull"], in: body, context: ctx)
        }
    }

    @Test
    func testABILoweringMarksSetCollectionHelpersAsNonThrowing() throws {
        expectNonThrowingCallees(try abiFunctions(["set_contains", "set_size"], in: RuntimeABISpec.collectionFunctions, privateBridge: true))
    }

    @Test
    func testBuildKIRLowersSetBinaryMembersToBundledSourceCalls() throws {
        let source = """
        fun main(values: Set<Int>, other: List<Int>) {
            values.intersect(other)
            values.union(other)
            values.subtract(other)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["intersect", "union", "subtract"], in: body, context: ctx)
        }
    }

    @Test
    func testBuildKIRKeepsListUnzipSourceBacked() throws {
        let source = """
        fun main(values: List<Pair<Int, String>>) {
            values.unzip()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["unzip"], in: body, context: ctx)
        }
    }

    @Test
    func testBuildKIRKeepsIterableUnzipSourceBacked() throws {
        let source = """
        fun main(values: Iterable<Pair<Int, String>>) {
            values.unzip()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["unzip"], in: body, context: ctx)
            let sequenceUnzip = try abiFunctions(["sequence_unzip"], in: RuntimeABISpec.sequenceFunctions)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(sequenceUnzip.allSatisfy { !callNames.contains($0.name) })
        }
    }

    @Test
    func testBuildKIRKeepsSequenceAssociateToSourceBacked() throws {
        let source = """
        fun main() {
            val source = sequenceOf("a", "bb")
            val destination = mutableMapOf<String, Int>()
            source.associateTo(destination) { it to it.length }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["associateTo"], in: body, context: ctx)
        }
    }

    @Test
    func testBuildKIRKeepsListZipWithNextOverloadsSourceBacked() throws {
        let source = """
        fun main(values: List<Int>) {
            values.zipWithNext()
            values.zipWithNext { left, right -> right - left }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let functions = try abiFunctions(
                ["list_zipWithNext", "list_zipWithNextTransform"],
                in: RuntimeABISpec.collectionHOFFunctions,
                privateBridge: true
            )
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(functions.allSatisfy { callNames.contains($0.name) })
            try expectDeclaredCallees(in: body, context: ctx)
        }
    }

    @Test
    func testBuildKIRMarksListChunkedBridgesAsThrowing() throws {
        let source = """
        fun main(values: List<Int>) {
            values.chunked(2)
            values.chunked(2) { chunk -> chunk.sum() }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let functions = try abiFunctions(
                ["list_chunked", "list_chunked_transform"],
                in: RuntimeABISpec.collectionHOFFunctions,
                privateBridge: true
            )
            #expect(functions.allSatisfy { $0.isThrowing })
            try expectRuntimeCalls(functions, in: body, interner: ctx.interner)
        }
    }

    /// KSP-626: `withIndex`/`forEachIndexed` are bundled Kotlin source, so they
    /// must lower to the source-backed declaration instead of a runtime bridge.
    @Test
    func testBuildKIRLowersListIndexedHelpersToBundledSourceCalls() throws {
        let source = """
        fun main(values: List<Int>) {
            values.withIndex()
            values.forEachIndexed { index, value -> println(index + value) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["withIndex", "forEachIndexed"], in: body, context: ctx)
        }
    }

    /// KSP-998: Iterable.withIndex() returns the source-backed lazy wrapper;
    /// acquiring its iterator must stay on the throwing Iterable bridge rather
    /// than the eager List or legacy range bridge.
    @Test
    func testBuildKIRLowersIterableWithIndexToLazyIterableIteratorBridge() throws {
        let source = """
        fun main(values: Iterable<Int>) {
            val indexed: Iterable<IndexedValue<Int>> = values.withIndex()
            indexed.iterator()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["withIndex"], in: body, context: ctx)
            let iterator = try abiFunctions(["iterable_iterator"], in: RuntimeABISpec.collectionBridgeFunctions)
            let eagerIterator = try abiFunctions(["range_iterator"], in: RuntimeABISpec.allFunctions)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(iterator.allSatisfy { callNames.contains($0.name) }, "Iterable.iterator() must use the lazy bridge")
            #expect(eagerIterator.allSatisfy { !callNames.contains($0.name) })
        }
    }

    /// KSP-977 / KUU-604: exact/custom Iterable and concrete List receivers
    /// bind to the bundled inline Iterable.forEach declaration. Other
    /// receiver-specific forEach families keep their existing lowering paths.
    @Test
    func testBuildKIRLowersIterableForEachWithoutHijackingOtherReceivers() throws {
        let source = """
        class CustomIterable<T>(private val values: List<T>) : Iterable<T> {
            override fun iterator(): Iterator<T> = values.iterator()
        }

        fun main(values: Iterable<Int>, custom: CustomIterable<Int>) {
            values.forEach { println(it) }
            custom.forEach { println(it) }
        }

        fun receiverFamilies(
            list: List<Int>,
            sequence: Sequence<Int>,
            iterator: Iterator<Int>,
            array: Array<Int>,
            primitiveArray: IntArray
        ) {
            list.forEach { println(it) }
            sequence.forEach { println(it) }
            iterator.forEach { println(it) }
            array.forEach { println(it) }
            primitiveArray.forEach { println(it) }
            list.forEachIndexed { index, value -> println(index + value) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let iterableBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["forEach"], in: iterableBody, context: ctx)
            let eagerForEach = try abiFunctions(["list_forEach"], in: RuntimeABISpec.collectionHOFFunctions)
            let iterableCallees = extractCallees(from: iterableBody, interner: ctx.interner)
            #expect(eagerForEach.allSatisfy { !iterableCallees.contains($0.name) })

            let familyBody = try findKIRFunctionBody(named: "receiverFamilies", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["forEach", "forEachIndexed"], in: familyBody, context: ctx)
            let familyCallees = extractCallees(from: familyBody, interner: ctx.interner)
            #expect(eagerForEach.allSatisfy { !familyCallees.contains($0.name) })
        }
    }

    @Test
    func testBuildKIRLowersListZipToPrivateBridge() throws {
        let source = """
        fun main(left: List<Int>, right: List<String>) {
            left.zip(right)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let functions = try abiFunctions(["list_zip"], in: RuntimeABISpec.collectionHOFFunctions, privateBridge: true)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(functions.allSatisfy { callNames.contains($0.name) })
            #expect(!containsKotlinCallee("zip", in: callNames))
            try expectDeclaredCallees(in: body, context: ctx)
        }
    }

    @Test
    func testBuildKIRKeepsIterableZipArrayOverloadsSourceBacked() throws {
        let source = """
        fun main(values: Iterable<Int>, other: Array<String>) {
            values.zip(other)
            values.zip(other) { left, right -> "$left$right" }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["zip"], in: body, context: ctx)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.filter { isKotlinCallee($0, named: "zip") }.count == 2)
            let bridges = try abiFunctions(
                ["list_zip", "list_zip_transform"],
                in: RuntimeABISpec.collectionHOFFunctions,
                privateBridge: true
            )
            #expect(bridges.allSatisfy { !callNames.contains($0.name) })
        }
    }

    @Test
    func testBuildKIRLowersStringZipOverloadsToBundledKotlinCalls() throws {
        let source = """
        fun main(left: String, right: CharSequence) {
            left.zip(right)
            left.zip(right) { a, b -> a }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["zip"], in: body, context: ctx)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.filter { isKotlinCallee($0, named: "zip") }.count == 2)
        }
    }

    @Test
    func testBuildKIRLowersCharSequenceCollectionSequenceMembersToBundledKotlinCalls() throws {
        let source = """
        fun main(value: CharSequence, other: CharSequence) {
            value.toSortedSet()
            value.toCollection(mutableListOf<Char>())
            value.withIndex()
            value.zipWithNext()
            value.zipWithNext { a, _ -> a }
            value.zip(other)
            value.zip(other) { a, _ -> a }
            value.chunkedSequence(2)
            value.chunkedSequence(2) { chunk -> chunk.length }
            value.windowedSequence(2, 1, true)
            value.windowedSequence(2, 1, true) { window -> window.length }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls([
                "toSortedSet", "toCollection", "withIndex", "zipWithNext", "zip",
                "chunkedSequence", "windowedSequence",
            ], in: body, context: ctx)
        }
    }

    // KSP-408: indexOfFirst/indexOfLast are bundled Kotlin source (StringIndexOf.kt).
    // KSP-410: the whole String HOF family is bundled Kotlin source
    // (StringHOF.kt), so none of it may lower to a `kk_string_*` call anymore.
    @Test
    func testBuildKIRLowersStringHOFToBundledKotlinCallsInsteadOfRuntimeCalls() throws {
        let source = """
        fun main(value: String) {
            value.map { c -> c }
            value.mapIndexed { index, _ -> index }
            value.mapNotNull { c -> if (c == 'a') 1 else null }
            value.firstNotNullOf { c -> if (c == 'a') 1 else null }
            value.firstNotNullOfOrNull { c -> if (c == 'b') 2 else null }
            value.sumBy { c -> c.code }
            value.partition { c -> c == 'a' }
            value.reduce { acc, c -> if (c > acc) c else acc }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls([
                "map", "mapIndexed", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull",
                "sumBy", "partition", "reduce",
            ], in: body, context: ctx)
        }
    }

    @Test
    func testBuildKIRLowersStringByteInputStreamToFlatRuntimeCalls() throws {
        let source = """
        import kotlin.text.Charsets

        fun main(value: String) {
            value.byteInputStream()
            value.byteInputStream(Charsets.UTF_16)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let functions = try abiFunctions(
                ["string_byteInputStream_flat", "string_byteInputStream_charset_flat"],
                in: RuntimeABISpec.fileIOFunctions,
                privateBridge: true
            )
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(functions.allSatisfy { callNames.contains($0.name) })
            try expectDeclaredCallees(in: body, context: ctx)
        }
    }

    @Test
    func testABILoweringMarksStringByteInputStreamFlatHelpersAsNonThrowing() throws {
        expectNonThrowingCallees(try abiFunctions(
            ["string_byteInputStream_flat", "string_byteInputStream_charset_flat"],
            in: RuntimeABISpec.fileIOFunctions,
            privateBridge: true
        ))
    }

    @Test
    func testBuildKIRPreservesSourceBackedStringEqualsCall() throws {
        let source = """
        fun main(lhs: String, rhs: String?) {
            lhs.equals(rhs)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            // The caller must retain the Kotlin declaration rather than its flat-string bridge.
            try expectSourceBackedCalls(["equals"], in: body, context: ctx)
            let flatEquals = try abiFunctions(["string_equals_flat"], in: RuntimeABISpec.stringFunctions, privateBridge: true)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(flatEquals.allSatisfy { !callNames.contains($0.name) })
        }
    }

    @Test
    func testABILoweringMarksStringEqualsFlatHelperAsNonThrowing() throws {
        expectNonThrowingCallees(try abiFunctions(["string_equals_flat"], in: RuntimeABISpec.stringFunctions, privateBridge: true))
        let interner = StringInterner()
        let classified = ABILoweringPass().nonThrowingCallees(interner: interner)
        let registered = Set(RuntimeABIExterns.allExterns.map { interner.intern($0.name) })
            .union(RuntimeABISpec.compilerInternalNonThrowingCalleeNames.map(interner.intern))
        #expect(classified.isSubset(of: registered))
    }

    @Test
    func testBuildKIRLowersMapWithDefaultToBundledSourceCall() throws {
        let source = """
        fun main(values: Map<Int, Int>) {
            values.withDefault { it * 10 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectSourceBackedCalls(["withDefault"], in: body, context: ctx)
        }
    }

    @Test
    func testBuildKIRLowersListWindowedToPrivateBridge() throws {
        let source = """
        fun main(values: List<Int>) {
            values.windowed(3)
            values.windowed(3, 2)
            values.windowed(3, 2, true)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let functions = try abiFunctions(["list_windowed"], in: RuntimeABISpec.collectionHOFFunctions, privateBridge: true)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(functions.allSatisfy { callNames.contains($0.name) })
            #expect(!containsKotlinCallee("windowed", in: callNames))
            try expectDeclaredCallees(in: body, context: ctx)
        }
    }

    @Test
    func testABILoweringMarksAtomicRuntimeHelpersAsNonThrowing() throws {
        expectNonThrowingCallees(try abiFunctions([
            "atomic_int_load", "atomic_int_store", "atomic_long_compareAndExchange", "atomic_ref_exchange",
        ], in: RuntimeABISpec.atomicFunctions, privateBridge: true))
    }

    @Test
    func testABILoweringMarksNativeRefRuntimeHelpersAsNonThrowing() throws {
        let publicFunctions = try abiFunctions([
            "weak_ref_create", "weak_ref_get", "weak_ref_clear", "cleaner_create", "cleaner_dispose",
            "gc_collect", "gc_schedule", "gc_target_heap_bytes", "gc_target_heap_utilization", "gc_max_heap_bytes",
            "debugging_gc_suspend_count", "debugging_thread_count", "debugging_global_object_count",
        ], in: RuntimeABISpec.nativeRefFunctions + RuntimeABISpec.memoryFunctions)
        let privateFunctions = try abiFunctions([
            "debugging_is_thread_state_runnable", "debugging_force_checked_shutdown_get",
            "debugging_force_checked_shutdown_set", "debugging_dump_memory",
        ], in: RuntimeABISpec.nativeRefFunctions, privateBridge: true)
        expectNonThrowingCallees(publicFunctions + privateFunctions)
    }

    @Test
    func testThisBasedMemberCallCompilesAndUsesImplicitReceiverInLowering() throws {
        let source = """
        class Vec
        fun Vec.plus(other: Vec): Vec = this
        fun Vec.combine(other: Vec): Vec = this.plus(other)
        fun useCombine(a: Vec, b: Vec): Vec = a.combine(b)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected this-based member call program to compile without errors.")

            let module = try #require(ctx.kir)
            let combineFunction = try findKIRFunction(named: "combine", in: module, interner: ctx.interner)
            let plusFunction = try findKIRFunction(named: "plus", in: module, interner: ctx.interner)
            let plusCall = try #require(combineFunction.body.compactMap { instruction -> (callee: InternedString, arguments: [KIRExprID])? in
                guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction,
                      symbol == plusFunction.symbol else { return nil }
                return (callee, arguments)
            }.first)
            #expect(plusCall.callee == plusFunction.name)

            let implicitReceiverSymbol = try #require(combineFunction.params.first?.symbol)
            #expect(plusCall.arguments.count == 2)
            guard case let .symbolRef(insertedReceiver)? = module.arena.expr(plusCall.arguments[0]) else {
                Issue.record("Expected first argument to be a symbolRef for implicit this receiver.")
                return
            }
            #expect(insertedReceiver == implicitReceiverSymbol)
        }
    }

    @Test
    func testABILoweringInsertsBoxingCallsForPrimitiveToAnyBoundary() throws {
        let source = """
        fun acceptAny(x: Any?) = x
        fun main() {
            acceptAny(42)
            acceptAny(true)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let functions = try abiFunctions(["box_int_static", "box_bool_static"], in: RuntimeABISpec.staticPrimitiveBoxingFunctions)
            try expectRuntimeCalls(functions, in: body, interner: ctx.interner)
        }
    }

    @Test
    func testABILoweringBoxingCallsAreNonThrowing() throws {
        let source = """
        fun acceptAny(x: Any?) = x
        fun main() {
            acceptAny(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            let functions = try abiFunctions(
                ["box_int_static", "box_bool_static", "unbox_int_static", "unbox_bool_static"],
                in: RuntimeABISpec.staticPrimitiveBoxingFunctions
            )
            #expect(functions.allSatisfy { !$0.isThrowing })
            let boxingThrowFlags = functions.flatMap { throwFlags[$0.name] ?? [] }
            #expect(!(boxingThrowFlags.isEmpty))
            #expect(boxingThrowFlags.allSatisfy { $0 == false })
        }
    }

    @Test
    func testStringStdlibThrowFlagsAreClassifiedByABI() throws {
        let source = """
        fun main() {
            val maybe: String? = null
            "  hi  ".trim()
            "1,2,3".split(",")
            "abcd".subSequence(1, 3)
            maybe.isNullOrEmpty()
            maybe.isNullOrBlank()
            "ab".repeat(2)
            "42".toInt()
            "3.14".toDouble()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            func importedFlags(_ name: String) -> [Bool]? {
                throwFlags.first { isKotlinCallee($0.key, named: name) }?.value
            }
            try expectDeclaredCallees(in: body, context: ctx)
            let sourceOnlyRuntimeAlternatives = try abiFunctions([
                "string_split_flat", "string_isNullOrEmpty_flat", "string_isNullOrBlank_flat",
            ], in: RuntimeABISpec.stringFunctions)
            #expect(sourceOnlyRuntimeAlternatives.allSatisfy { throwFlags[$0.name] == nil })
            #expect(importedFlags("split") != nil)
            // KSP-414: toInt is imported from the artifact rather than routed
            // through a public kk_string_toInt_flat helper.
            #expect(importedFlags("toInt")?.allSatisfy { $0 == true } == true)
            let toDouble = try abiFunctions(["string_toDouble_flat"], in: RuntimeABISpec.stringFunctions, privateBridge: true)
            #expect(toDouble.allSatisfy { $0.isThrowing })
            try expectRuntimeCalls(toDouble, in: body, interner: ctx.interner)
        }
    }

    @Test
    func testArrayAccessAndAssignmentLowerToRuntimeCallsWithExpectedThrowFlags() throws {
        let source = """
        fun main(): Any? {
            val arr = IntArray(2)
            arr[0] = 7
            return arr[0]
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            // Size-only IntArray(n) lowers to kk_array_new_checked (throws on
            // negative size), not bare kk_array_new.
            try expectArrayRuntimeCallsThrow(body: body, interner: ctx.interner)
        }
    }

    @Test
    func testPrimitiveArrayHOFsRemainBundledSourceCalls() throws {
        let source = """
        fun main(): Any? {
            val values = intArrayOf(1, 2, 3)
            val mapped = values.map { it * 2 }
            val mappedNotNull = values.mapNotNull { if (it > 1) it.toString() else null }
            val unsignedValues = UByteArray(3) { (it + 1).toUByte() }
            val unsignedMappedNotNull = unsignedValues.mapNotNull {
                if (it.toInt() > 1) it.toString() else null
            }
            val total = values.fold(0) { accumulator, value -> accumulator + value }
            val rendered = values.joinToString(transform = { it.toString() })
            return listOf(mapped, mappedNotNull, unsignedMappedNotNull, total, rendered)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(containsKotlinCallee("map", in: callNames))
            // Both signed and unsigned primitive-array calls must bind to source.
            #expect(callNames.filter { isKotlinCallee($0, named: "mapNotNull") }.count == 2)
            #expect(containsKotlinCallee("fold", in: callNames))
            // Source-backed default lowering may retain the default suffix or
            // emit the resolved source function name directly.
            #expect(
                containsKotlinCallee("joinToString", in: callNames) ||
                    containsKotlinCallee("joinToString$default", in: callNames)
            )
            try expectDeclaredCallees(in: body, context: ctx)
        }
    }

    @Test
    func testUShortArrayLoweringUsesSharedArrayRuntimeCalls() throws {
        let source = """
        fun main(): UShort {
            val arr = UShortArray(2) { (it + 1).toUShort() }
            arr[0] = 65535.toUShort()
            return arr[0]
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectArrayRuntimeCallsThrow(body: body, interner: ctx.interner)
        }
    }

    @Test
    func testUShortArrayStorageConstructorUsesSignedArrayViewBridge() throws {
        let source = """
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        fun main(): Short {
            val storage = shortArrayOf(1, -1)
            val values = UShortArray(storage)
            return values.asShortArray()[1]
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let viewBridge = try abiFunctions(["shortArray_asUShortArray"], in: RuntimeABISpec.collectionFunctions, privateBridge: true)
            let objectAllocation = try abiFunctions(["object_new"], in: RuntimeABISpec.arrayFunctions)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(viewBridge.allSatisfy { callNames.contains($0.name) })
            #expect(containsKotlinCallee("asShortArray", in: callNames))
            #expect(objectAllocation.allSatisfy { !callNames.contains($0.name) })
        }
    }

    @Test
    func testUIntArrayAccessAndFactoriesLowerToRuntimeCallsAndResolveUIntArrayType() throws {
        let source = """
        fun make() = uintArrayOf(1u, 2u)
        fun main(): Any? {
            val arr = UIntArray(2) { (it + 1).toUInt() }
            arr[0] = 7u
            val fromFactory = make()
            return arr[0].toInt() + fromFactory[1].toInt()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let sema = try #require(ctx.sema)
            let makeSymbol = try #require(sema.symbols.lookupByShortName(ctx.interner.intern("make")).first)
            let signature = try #require(sema.symbols.functionSignature(for: makeSymbol))
            guard case let .classType(classType) = sema.types.kind(of: signature.returnType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected make() to return a nominal UIntArray type.")
                return
            }
            let uintArraySymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "UIntArray"].map(ctx.interner.intern)))
            #expect(symbol.id == uintArraySymbol)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            try expectArrayRuntimeCallsThrow(body: body, interner: ctx.interner)

            let makeBody = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let makeCallNames = extractCallees(from: makeBody, interner: ctx.interner)
            let allocation = try abiFunctions(["array_new"], in: RuntimeABISpec.arrayFunctions)
            let stores = try abiFunctions(["array_set"], in: RuntimeABISpec.arrayFunctions)
            let genericFactory = try abiFunctions(["array_of"], in: RuntimeABISpec.collectionFunctions)
            #expect(allocation.allSatisfy { makeCallNames.contains($0.name) })
            #expect(stores.allSatisfy { function in makeCallNames.filter { $0 == function.name }.count == 2 })
            #expect(genericFactory.allSatisfy { !makeCallNames.contains($0.name) })
            #expect(!makeCallNames.contains("uintArrayOf"))
        }
    }

    @Test
    func testMapGetValueLoweringMarksRuntimeCallAsThrowing() throws {
        let source = """
        fun main(): Int {
            val map = mapOf("a" to 1)
            return map.getValue("b")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)

            #expect(throwFlags["getValue"]?.allSatisfy { $0 == true } == true, "Map.getValue should be lowered as throwing so ABI lowering wires outThrown.")
        }
    }

    @Test
    func testArrayOutOfBoundsThrownChannelReturnsEarlyBeforeSubsequentReturn() throws {
        let source = """
        fun readOutOfBounds(arr: Any?): Any? = arr[5]
        fun main(): Any? {
            val arr = IntArray(1)
            readOutOfBounds(arr)
            return 99
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ArrayThrownChannel",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            #expect(FileManager.default.fileExists(atPath: outputPath))
            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: outputPath, arguments: [])
                Issue.record("Expected top-level thrown channel to fail process exit.")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                result = failed
            } catch {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(result.exitCode == 1)
            #expect(result.stderr.contains("KSWIFTK-LINK-0003"))
        }
    }

    @Test
    func testMutableListIndexedMutationUsesThrowingABI() throws {
        let source = """
        fun main(): Any? {
            val values = mutableListOf(10, 20)
            values.add(1, 15)
            values[0] = 5
            return values[0]
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let functions = try abiFunctions(["mutable_list_add_at", "mutable_list_set"], in: RuntimeABISpec.collectionFunctions, privateBridge: true)
            #expect(functions.allSatisfy { $0.isThrowing })
            try expectRuntimeCalls(functions, in: body, interner: ctx.interner)
        }
    }

    @Test
    func testCollectionMutationCallsUseThrowingABI() throws {
        let source = """
        fun main(list: MutableList<Int>, set: MutableSet<Int>, map: MutableMap<String, Int>) {
            list.add(1)
            set.add(1)
            map.put("a", 1)
            map.remove("a")
            map.clear()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let functions = try abiFunctions([
                "mutable_list_add", "mutable_set_add", "mutable_map_put", "mutable_map_remove", "mutable_map_clear",
            ], in: RuntimeABISpec.collectionFunctions, privateBridge: true)
            #expect(functions.allSatisfy { $0.isThrowing })
            try expectRuntimeCalls(functions, in: body, interner: ctx.interner)
        }
    }

    @Test
    func testFrontendAndSemaResolveTypedDeclarationsAndEmitExpectedDiagnostics() throws {
        let source = """
        package typed.demo
        import typed.demo.*

        public inline suspend fun transform<T>(
            vararg values: T,
            crossinline mapper: T,
            noinline fallback: T = mapper
        ): String? = "ok"
        fun String.decorate(): String = this

        fun typed(a: Int, b: String?, c: Any): Int = 1
        fun duplicate(x: Int, x: Int): Int = x

        val explicit: Int = 1
        var delegated by delegateProvider
        val unknown: CustomType = explicit
        val explicit: Int = 2

        class TypedBox<T>(value: T)
        object Obj
        typealias Alias = String
        enum class Kind { A, B }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "Typed", emit: .kirDump)
            try runToKIR(ctx)

            let ast = try #require(ctx.ast)
            let declarations = ast.arena.declarations()
            #expect(declarations.count >= 8)

            var sawTypedParameter = false
            var sawFunctionReturnType = false
            var sawFunctionReceiverType = false
            var sawExplicitPropertyType = false
            var sawDelegatedPropertyWithoutType = false

            for decl in declarations {
                switch decl {
                case let .funDecl(fn):
                    if fn.returnType != nil {
                        sawFunctionReturnType = true
                    }
                    if fn.receiverType != nil {
                        sawFunctionReceiverType = true
                    }
                    if fn.valueParams.contains(where: { $0.type != nil }) {
                        sawTypedParameter = true
                    }
                case let .propertyDecl(property):
                    if let typeID = property.type, let typeRef = ast.arena.typeRef(typeID) {
                        sawExplicitPropertyType = true
                        if case let .named(path, _, _) = typeRef {
                            #expect(!(path.isEmpty))
                        }
                    } else if property.delegateExpression != nil {
                        sawDelegatedPropertyWithoutType = true
                    }
                default:
                    continue
                }
            }

            #expect(sawTypedParameter)
            #expect(sawFunctionReturnType)
            #expect(sawFunctionReceiverType)
            #expect(sawExplicitPropertyType)
            #expect(sawDelegatedPropertyWithoutType)

            let sema = try #require(ctx.sema)
            #expect(!(sema.symbols.allSymbols().isEmpty))
            #expect(!(sema.bindings.exprTypes.isEmpty))
            let decorateSymbol = try #require(sema.symbols.lookup(fqName: ["typed", "demo", "decorate"].map(ctx.interner.intern)))
            let signature = try #require(sema.symbols.functionSignature(for: decorateSymbol))
            #expect(signature.receiverType == sema.types.stringType)

            let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
            #expect(codes.contains("KSWIFTK-TYPE-0002"))
            #expect(codes.contains("KSWIFTK-SEMA-0001"))
        }
    }

    @Test
    func testRepeatLabeledReturnJumpsToIterationEndInsteadOfReturningFromEnclosingFunction() throws {
        for (label, source) in [
            ("implicit", "fun main() { var s = 0; repeat(5) { if (it == 3) return@repeat; s += it }; println(s) }"),
            ("explicit", "fun main() { var s = 0; repeat(5) lbl@{ if (it == 3) return@lbl; s += it }; println(s) }"),
        ] {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
                try runToKIR(ctx)
                let module = try #require(ctx.kir)
                let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
                let returnCount = body.filter { instruction in
                    if case .returnUnit = instruction { return true }
                    return false
                }.count
                // Only the implicit trailing return of `main` may remain (\(label)).
                #expect(returnCount <= 1, "\(label): return@ must not return from the enclosing function")
            }
        }
    }
}
