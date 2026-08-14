@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct BuildKIRCodegenRegressionTests {
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("first"))
            #expect(callNames.contains("firstOrNull"))
            #expect(callNames.contains("lastOrNull"))
            #expect(!(callNames.contains("kk_list_first")))
            #expect(!(callNames.contains("kk_list_firstOrNull")))
            #expect(!(callNames.contains("kk_list_lastOrNull")))
        }
    }

    @Test
    func testABILoweringMarksSetCollectionHelpersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_list_intersect")))
        #expect(callees.contains(interner.intern("kk_list_union")))
        #expect(callees.contains(interner.intern("kk_list_subtract")))
        #expect(callees.contains(interner.intern("__kk_set_contains")))
        #expect(callees.contains(interner.intern("__kk_set_size")))
    }

    @Test
    func testBuildKIRLowersListUnionToCollectionRuntimeCall() throws {
        let source = """
        fun main(values: List<Int>, other: List<Int>) {
            values.union(other)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("kk_list_union"))
            #expect(!(callNames.contains("union")))
        }
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("intersect"))
            #expect(callNames.contains("union"))
            #expect(callNames.contains("subtract"))
            #expect(!(callNames.contains("kk_set_intersect")))
            #expect(!(callNames.contains("kk_set_union")))
            #expect(!(callNames.contains("kk_set_subtract")))
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("unzip"))
            #expect(!(callNames.contains("kk_list_unzip")))
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("associateTo"))
            #expect(!(callNames.contains("kk_list_associateTo")))
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("__kk_list_zipWithNext"))
            #expect(callNames.contains("__kk_list_zipWithNextTransform"))
            #expect(!(callNames.contains("kk_list_zipWithNext")))
            #expect(!(callNames.contains("kk_list_zipWithNextTransform")))
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("withIndex"))
            #expect(callNames.contains("forEachIndexed"))
            #expect(!(callNames.contains("kk_list_withIndex")))
            #expect(!(callNames.contains("kk_list_forEachIndexed")))
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("__kk_list_zip"))
            #expect(!(callNames.contains("zip")))
            #expect(!(callNames.contains("kk_list_zip")))
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            for removedName in [
                "kk_string_zip",
                "kk_string_zipTransform",
                "kk_string_zip_flat",
                "kk_string_zipTransform_flat",
            ] {
                #expect(!(callNames.contains(removedName)))
            }
        }
    }

    @Test
    func testBuildKIRLowersCharSequenceCollectionSequenceMembersToFlatRuntimeCalls() throws {
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            let flatNames = [
                "kk_string_toSortedSet_flat",
                "kk_string_toCollection_flat",
                "kk_string_withIndex_flat",
            ]
            for flatName in flatNames {
                #expect(callNames.contains(flatName), "Missing \(flatName)")
            }

            let removedNames = [
                "kk_string_zipWithNext_flat",
                "kk_string_zipWithNextTransform_flat",
                "kk_string_zip_flat",
                "kk_string_zipTransform_flat",
                "kk_string_chunked_sequence_flat",
                "kk_string_chunked_sequence_transform_flat",
                "kk_string_windowedSequence_partial_flat",
                "kk_string_windowedSequence_transform_flat",
                "kk_string_zipWithNext",
                "kk_string_zipWithNextTransform",
                "kk_string_zip",
                "kk_string_zipTransform",
                "kk_string_chunked_sequence",
                "kk_string_chunked_sequence_transform",
                "kk_string_windowedSequence_partial",
                "kk_string_windowedSequence_transform",
            ]
            for removedName in removedNames {
                #expect(!(callNames.contains(removedName)))
            }

            let rawNames = [
                "kk_string_toSortedSet",
                "kk_string_toCollection",
                "kk_string_withIndex",
            ]
            for rawName in rawNames {
                #expect(!(callNames.contains(rawName)), "Unexpected raw CharSequence String call \(rawName)")
            }
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            let migrated = [
                "map", "mapIndexed", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull",
                "sumBy", "partition", "reduce",
            ]
            for name in migrated {
                #expect(
                    !callNames.contains("kk_string_\(name)") && !callNames.contains("kk_string_\(name)_flat"),
                    "String.\(name) must not lower to a runtime call"
                )
            }
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            let flatNames = [
                "kk_string_byteInputStream_flat",
                "kk_string_byteInputStream_charset_flat",
            ]
            for flatName in flatNames {
                #expect(callNames.contains(flatName), "Missing \(flatName)")
            }
            let rawNames = flatNames.map { String($0.dropLast("_flat".count)) }
            for rawName in rawNames {
                #expect(!(callNames.contains(rawName)), "Unexpected raw String stream call \(rawName)")
            }
        }
    }

    @Test
    func testABILoweringMarksStringByteInputStreamFlatHelpersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        for flatName in [
            "kk_string_byteInputStream_flat",
            "kk_string_byteInputStream_charset_flat",
        ] {
            #expect(callees.contains(interner.intern(flatName)), "Missing \(flatName)")
        }
    }

    @Test
    func testBuildKIRLowersStringEqualsToFlatRuntimeCall() throws {
        let source = """
        fun main(lhs: String, rhs: String?) {
            lhs.equals(rhs)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("kk_string_equals_flat"))
            #expect(!(callNames.contains("kk_string_equals")))
        }
    }

    @Test
    func testABILoweringMarksStringEqualsFlatHelperAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_string_equals_flat")))
        #expect(!(callees.contains(interner.intern("kk_string_equals"))))
    }

    @Test
    func testBuildKIRLowersMapWithDefaultToBundledSourceCall() throws {
        let source = """
        fun main(values: Map<Int, Int>) {
            values.withDefault { it * 10 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("withDefault"))
            #expect(!(callNames.contains("kk_map_withDefault")))
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("__kk_list_windowed"))
            #expect(!(callNames.contains("windowed")))
            #expect(!(callNames.contains("kk_list_windowed_default")))
            #expect(!(callNames.contains("kk_list_windowed")))
            #expect(!(callNames.contains("kk_list_windowed_partial")))
        }
    }

    @Test
    func testABILoweringMarksAtomicRuntimeHelpersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_atomic_int_load")))
        #expect(callees.contains(interner.intern("kk_atomic_int_store")))
        #expect(callees.contains(interner.intern("kk_atomic_long_compareAndExchange")))
        #expect(callees.contains(interner.intern("kk_atomic_ref_exchange")))
    }

    @Test
    func testABILoweringMarksNativeRefRuntimeHelpersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_weak_ref_create")))
        #expect(callees.contains(interner.intern("kk_weak_ref_get")))
        #expect(callees.contains(interner.intern("kk_weak_ref_clear")))
        #expect(callees.contains(interner.intern("kk_cleaner_create")))
        #expect(callees.contains(interner.intern("kk_cleaner_dispose")))
        #expect(callees.contains(interner.intern("kk_gc_collect")))
        #expect(callees.contains(interner.intern("kk_gc_schedule")))
        #expect(callees.contains(interner.intern("kk_gc_target_heap_bytes")))
        #expect(callees.contains(interner.intern("kk_gc_target_heap_utilization")))
        #expect(callees.contains(interner.intern("kk_gc_max_heap_bytes")))
        #expect(callees.contains(interner.intern("kk_debugging_is_thread_state_runnable")))
        #expect(callees.contains(interner.intern("kk_debugging_gc_suspend_count")))
        #expect(callees.contains(interner.intern("kk_debugging_thread_count")))
        #expect(callees.contains(interner.intern("kk_debugging_global_object_count")))
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
            let plusCall = try #require(combineFunction.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "plus"
            })
            guard case let .call(_, _, arguments, _, _, _, _, _) = plusCall else {
                Issue.record("Expected combine to lower to a call to plus.")
                return
            }

            let implicitReceiverSymbol = try #require(combineFunction.params.first?.symbol)
            #expect(arguments.count == 2)
            guard case let .symbolRef(insertedReceiver)? = module.arena.expr(arguments[0]) else {
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
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.contains("kk_box_int"))
            #expect(callNames.contains("kk_box_bool"))
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

            let boxingThrowFlags = body.compactMap { instruction -> Bool? in
                guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else {
                    return nil
                }
                let name = ctx.interner.resolve(callee)
                guard name == "kk_box_int" || name == "kk_box_bool" ||
                    name == "kk_unbox_int" || name == "kk_unbox_bool"
                else {
                    return nil
                }
                return canThrow
            }
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
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            func flags(_ primary: String, _ aliases: String...) -> [Bool]? {
                ([primary] + aliases).compactMap { throwFlags[$0] }.first
            }
            #expect(throwFlags["kk_string_split_flat"] == nil)
            #expect(throwFlags["kk_string_split"] == nil)
            #expect(throwFlags["split"] != nil)
            // KSP-406: subSequence is bundled Kotlin source (delegates to substring),
            // so it no longer lowers to a String-specific runtime helper.
            #expect(throwFlags["kk_string_subSequence_flat"] == nil)
            #expect(throwFlags["kk_string_subSequence"] == nil)
            #expect(throwFlags["kk_string_substring_flat"] == nil)
            #expect(throwFlags["kk_string_substring"] == nil)
            #expect(flags("kk_string_isNullOrEmpty", "kk_string_isNullOrEmpty_flat", "__string_isNullOrEmpty_flat") == nil)
            #expect(flags("kk_string_isNullOrBlank", "kk_string_isNullOrBlank_flat", "__string_isNullOrBlank_flat") == nil)
            #expect(throwFlags["kk_string_repeat_flat"] == nil)
            #expect(throwFlags["kk_string_repeat"] == nil)
            // KSP-414: toInt is source-backed and lowers through the source
            // function `toInt` rather than a public kk_string_toInt_flat helper.
            #expect(throwFlags["toInt"]?.allSatisfy { $0 == true } == true)
            #expect(throwFlags["__kk_string_toDouble_flat"]?.allSatisfy { $0 == true } == true)
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
            let callNames = extractCallees(from: body, interner: ctx.interner)
            // Size-only IntArray(n) lowers to kk_array_new_checked (throws on
            // negative size), not bare kk_array_new.
            #expect(callNames.contains("kk_array_new_checked"))
            #expect(callNames.contains("kk_array_set"))
            #expect(callNames.contains("kk_array_get"))

            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags["kk_array_new_checked"]?.allSatisfy { $0 == true } == true)
            #expect(throwFlags["kk_array_set"]?.allSatisfy { $0 == true } == true)
            #expect(throwFlags["kk_array_get"]?.allSatisfy { $0 == true } == true)
        }
    }

    @Test
    func testPrimitiveArrayHOFsRemainBundledSourceCalls() throws {
        let source = """
        fun main(): Any? {
            val values = intArrayOf(1, 2, 3)
            val mapped = values.map { it * 2 }
            val total = values.fold(0) { accumulator, value -> accumulator + value }
            val rendered = values.joinToString(transform = { it.toString() })
            return listOf(mapped, total, rendered)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            #expect(callNames.contains("map"))
            #expect(callNames.contains("fold"))
            #expect(callNames.contains("joinToString$default"))
            #expect(!callNames.contains("kk_array_map"))
            #expect(!callNames.contains("kk_array_fold"))
            #expect(!callNames.contains("kk_array_joinToString_transform"))
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
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.contains("kk_array_new_checked"))
            #expect(callNames.contains("kk_array_set"))
            #expect(callNames.contains("kk_array_get"))

            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags["kk_array_new_checked"]?.allSatisfy { $0 == true } == true)
            #expect(throwFlags["kk_array_set"]?.allSatisfy { $0 == true } == true)
            #expect(throwFlags["kk_array_get"]?.allSatisfy { $0 == true } == true)
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
            #expect(ctx.interner.resolve(symbol.name) == "UIntArray")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.contains("kk_array_new_checked"))
            #expect(callNames.contains("kk_array_set"))
            #expect(callNames.contains("kk_array_get"))

            let makeBody = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let makeCallNames = extractCallees(from: makeBody, interner: ctx.interner)
            #expect(makeCallNames.contains("kk_array_of"))
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
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.contains("__kk_mutable_list_add_at"))
            #expect(callNames.contains("__kk_mutable_list_set"))

            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags["__kk_mutable_list_add_at"]?.allSatisfy { $0 == true } == true)
            #expect(throwFlags["__kk_mutable_list_set"]?.allSatisfy { $0 == true } == true)
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
                    } else if ctx.interner.resolve(property.name) == "delegated" {
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
            let decorateSymbol = sema.symbols.allSymbols().first(where: { symbol in
                ctx.interner.resolve(symbol.name) == "decorate"
            })
            #expect(decorateSymbol != nil)
            if let decorateSymbol {
                let signature = sema.symbols.functionSignature(for: decorateSymbol.id)
                #expect(signature?.receiverType != nil)
            }

            let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
            #expect(codes.contains("KSWIFTK-TYPE-0002"))
            #expect(codes.contains("KSWIFTK-SEMA-0001"))
        }
    }
}
