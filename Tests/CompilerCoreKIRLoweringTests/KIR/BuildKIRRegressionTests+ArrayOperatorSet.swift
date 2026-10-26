#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test func testBuildKIRPreservesArrayOperatorSetBindings() throws {
        let source = """
        data class Point(val x: Int, val y: Int)
        operator fun Array<CharArray>.set(at: Point, value: Char) {
            this[at.y][at.x] = value
        }
        operator fun Array<CharArray>.set(x: Int, y: Int, value: Char) {
            this[y][x] = value
        }
        operator fun IntArray.set(at: Long, value: Int) { this[at.toInt()] = value }
        fun pointWrite(grid: Array<CharArray>, at: Point) { grid[at] = '.' }
        fun multiWrite(grid: Array<CharArray>) { grid[0, 0] = '.' }
        fun longWrite(array: IntArray) { array[0L] = 7 }
        fun canonicalWrite(array: Array<Int>, ints: IntArray, chars: CharArray, index: Int) {
            array[index] = 3
            ints[index] = 4
            chars[index] = '.'
        }
        fun erasedWrite(array: Array<*>) {
            val erased = array as Array<Any?>
            erased[0] = 42
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        for (name, argumentCount) in [("pointWrite", 3), ("multiWrite", 4), ("longWrite", 3)] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (SymbolID?, Int)? in
                guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "set" else { return nil }
                return (symbol, arguments.count)
            }
            #expect(calls.count == 1)
            let call = try #require(calls.first)
            #expect(call.0 != nil, "User operator set must retain its chosen symbol")
            #expect(call.1 == argumentCount)
            #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.arraySet)))
        }
        for (name, writeCount) in [("canonicalWrite", 3), ("erasedWrite", 1)] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.filter { $0 == runtimeCallee(.arraySet) }.count == writeCount)
            #expect(!callees.contains("set"))
        }
    }
}
#endif
