#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    // Regression coverage for a bug where `field += x` / `field++` on a
    // `private var` instance property (accessed via implicit `this`) silently
    // dropped the write: it only updated the KIR lowering context's
    // local-value cache (meant for real locals/params) instead of storing
    // back through the object's field offset, so the mutation never persisted.
    // Plain reassignment (`field = field + x`) already went through the
    // correct `kk_array_set` write-back path, which is why rewriting the
    // compound assign as an explicit reassignment was a working workaround.

    @Test func testCompoundAssignOnInstanceFieldEmitsFieldLoadAndStore() throws {
        let source = """
        class Counter(private var addend: Int) {
            fun bump(): Int {
                addend += 362437
                return addend
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "bump", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.arrayGetInbounds)), "Expected a field load before the compound assign, got: \(callees)")
        #expect(callees.contains(runtimeCallee(.arraySet)), "Expected the compound assign to write back through the field offset, got: \(callees)")

        let getIndex = callees.firstIndex(of: runtimeCallee(.arrayGetInbounds))
        let setIndex = callees.firstIndex(of: runtimeCallee(.arraySet))
        #expect(getIndex != nil && setIndex != nil && getIndex! < setIndex!, "Expected the field load to precede the field store, got: \(callees)")
    }

    @Test func testIncrementOnInstanceFieldEmitsFieldLoadAndStore() throws {
        let source = """
        class Holder(private var n: Int) {
            fun bump(): Int {
                n++
                return n
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "bump", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains(runtimeCallee(.arrayGetInbounds)), "Expected a field load before the increment, got: \(callees)")
        #expect(callees.contains(runtimeCallee(.arraySet)), "Expected the increment to write back through the field offset, got: \(callees)")
    }

    @Test func testCompoundAssignOnMultipleInstanceFieldsUsesDistinctOffsets() throws {
        let source = """
        class Pair(private var a: Int, private var b: Int) {
            fun bump(): Int {
                a += 1
                b += 2
                return a + b
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "bump", in: module, interner: ctx.interner)

        // Resolve each `kk_array_set` call's offset argument (arguments[1]) back to
        // the Int64 literal bound to it by a preceding `.constValue` instruction, so
        // we can assert the two stores actually target distinct field offsets rather
        // than just counting how many stores were emitted.
        var intLiteralByResult: [KIRExprID: Int64] = [:]
        for instruction in body {
            if case let .constValue(result, .intLiteral(value)) = instruction {
                intLiteralByResult[result] = value
            }
        }
        let storeOffsets = body.compactMap { instruction -> Int64? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  callee == ctx.interner.intern(runtimeCallee(.arraySet)),
                  arguments.count == 3
            else { return nil }
            return intLiteralByResult[arguments[1]]
        }

        #expect(storeOffsets.count == 2, "Expected two field stores (one per field), got \(storeOffsets.count)")
        #expect(Set(storeOffsets).count == 2, "Expected the two field stores to target distinct offsets, got \(storeOffsets)")
    }

    // KUU-4437: `count++` / `count += v` on an abstract or interface member
    // property has no backing-field slot to store into. The bare-name
    // compound-assign path used to fall through to the local-value cache and
    // silently drop the write; it must now delegate to the member
    // compound-assign lowering, which reads and writes through the
    // itable/vtable accessors.

    @Test func testCompoundAssignOnInterfacePropertyDispatchesThroughItable() throws {
        let source = """
        interface Counter {
            var count: Int
            fun inc() { count++ }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "inc", in: module, interner: ctx.interner)
        let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)

        #expect(virtualCallees.filter { $0 == "get" }.count == 1,
                "Expected the compound assign to read through the itable getter, got: \(virtualCallees)")
        #expect(virtualCallees.filter { $0 == "set" }.count == 1,
                "Expected the compound assign to write through the itable setter, got: \(virtualCallees)")
        #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.arraySet)),
                "An interface property has no field offset to store through")
    }

    @Test func testCompoundAssignOnAbstractClassPropertyDispatchesThroughVtable() throws {
        let source = """
        abstract class Counter {
            abstract var count: Int
            fun inc() { count += 1 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "inc", in: module, interner: ctx.interner)
        let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)

        #expect(virtualCallees.filter { $0 == "get" }.count == 1,
                "Expected the compound assign to read through the vtable getter, got: \(virtualCallees)")
        #expect(virtualCallees.filter { $0 == "set" }.count == 1,
                "Expected the compound assign to write through the vtable setter, got: \(virtualCallees)")
        #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.arraySet)),
                "An abstract property has no field offset to store through")
    }

    @Test func testAssignOnAbstractClassPropertyDispatchesThroughVtableSetter() throws {
        let source = """
        abstract class Counter {
            abstract var count: Int
            fun reset() { count = 0 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "reset", in: module, interner: ctx.interner)
        let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)

        #expect(virtualCallees.filter { $0 == "set" }.count == 1,
                "Expected the assignment to write through the vtable setter, got: \(virtualCallees)")
    }

    // KUU-4437 follow-up: an `open var` has backing storage, but a subclass
    // override shadows this declaration's field slot. Bare-name writes must
    // dispatch through the vtable accessors exactly like the explicit-
    // receiver path (BUG-227), not store at the declaring class's offset.

    @Test func testCompoundAssignOnOpenPropertyWithOverrideDispatchesVirtually() throws {
        let source = """
        open class Base {
            open var count = 0
            fun inc() { count++ }
        }
        class Sub : Base() { override var count = 100 }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "inc", in: module, interner: ctx.interner)
        let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)

        #expect(virtualCallees.filter { $0 == "get" }.count == 1,
                "Expected the compound assign to read through the vtable getter, got: \(virtualCallees)")
        #expect(virtualCallees.filter { $0 == "set" }.count == 1,
                "Expected the compound assign to write through the vtable setter, got: \(virtualCallees)")
        #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.arraySet)),
                "An overridable property must not store at the declaring class's field offset")
    }

    @Test func testAssignOnOpenPropertyWithOverrideDispatchesThroughVtableSetter() throws {
        let source = """
        open class Base {
            open var count = 0
            fun reset() { count = 0 }
        }
        class Sub : Base() { override var count = 100 }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "reset", in: module, interner: ctx.interner)
        let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)

        #expect(virtualCallees.filter { $0 == "set" }.count == 1,
                "Expected the assignment to write through the vtable setter, got: \(virtualCallees)")
        #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.arraySet)),
                "An overridable property must not store at the declaring class's field offset")
    }
}
#endif
