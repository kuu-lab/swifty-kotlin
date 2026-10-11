#if canImport(Testing)
@testable import Runtime
import RuntimeABI
import Foundation
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeProcessArgumentsTests {
    private func withArgv<T>(
        _ strings: [String],
        _ body: (UnsafeRawPointer, [UnsafeMutablePointer<UInt8>]) throws -> T
    ) rethrows -> T {
        let buffers = strings.map { text -> UnsafeMutablePointer<UInt8> in
            let bytes = Array(text.utf8) + [0]
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
            bytes.withUnsafeBufferPointer { buffer.initialize(from: $0.baseAddress!, count: $0.count) }
            return buffer
        }
        let vector = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: buffers.count + 1)
        vector.initialize(repeating: nil, count: buffers.count + 1)
        for (index, buffer) in buffers.enumerated() { vector[index] = UnsafePointer(buffer) }
        defer {
            vector.deinitialize(count: buffers.count + 1)
            vector.deallocate()
            for buffer in buffers { buffer.deallocate() }
        }
        return try body(UnsafeRawPointer(vector), buffers)
    }

    private func strings(_ raw: Int) throws -> [String] {
        let box = try #require(runtimeArrayBox(from: raw))
        return try box.elements.map { element in
            #expect(element != 0)
            #expect(runtimeStringBox(fromRaw: element) != nil)
            return try #require(runtimeStringFromRaw(element))
        }
    }

    @Test
    func zeroArgcAndProgramOnlyProduceTypedEmptyArrays() throws {
        let zero = __kk_process_args_from_argv(0, nil)
        let programOnly = withArgv(["/tmp/program"]) { argv, _ in
            __kk_process_args_from_argv(1, argv)
        }
        let negative = __kk_process_args_from_argv(Int32.min, nil)
        let defensiveNil = __kk_process_args_from_argv(2, nil)
        for raw in [zero, programOnly, negative, defensiveNil] {
            #expect(try strings(raw).isEmpty)
            #expect(runtimeArrayHasType(rawValue: raw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array")))
        }
    }

    @Test
    func dropsProgramNameButPreservesEmptyAndUnicodeArguments() throws {
        let expected = ["", "alpha", "日本語", "😀", "e\u{301}", "a b;\"'$()`[]{}"]
        let raw = withArgv(["program"] + expected) { argv, _ in
            __kk_process_args_from_argv(Int32(expected.count + 1), argv)
        }
        #expect(try strings(raw) == expected)
        let box = try #require(runtimeArrayBox(from: raw))
        let emoji = try #require(runtimeStringBox(fromRaw: box[3]))
        let decomposed = try #require(runtimeStringBox(fromRaw: box[4]))
        #expect(emoji.utf16CodeUnits == [0xD83D, 0xDE00])
        #expect(decomposed.utf16CodeUnits == [0x0065, 0x0301])
    }

    @Test
    func arrayAndStringValuesOutliveBorrowedArgvStorage() throws {
        let raw = try withArgv(["program", "original"]) { argv, buffers in
            let result = __kk_process_args_from_argv(2, argv)
            // Mutate the foreign memory immediately after conversion.
            buffers[1][0] = UInt8(ascii: "X")
            let preservedStrings = try strings(result)
            #expect(preservedStrings == ["original"])
            return result
        }
        // Both the vector and C-string buffers have been freed at this point.
        #expect(try strings(raw) == ["original"])
    }

    @Test
    func startupBridgeUsesExactCWidthsWithoutThrownParameter() throws {
        let specs = RuntimeABISpec.allFunctions.filter { $0.name == "__kk_process_args_from_argv" }
        #expect(specs.count == 1)
        let spec = try #require(specs.first)
        #expect(spec.parameters == [
            RuntimeABIParameter(name: "argc", type: .int32),
            RuntimeABIParameter(name: "argv", type: .nullableConstRawPointer),
        ])
        #expect(spec.returnType == .intptr)
        #expect(!spec.isThrowing)
    }
}
#endif
