#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {

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
