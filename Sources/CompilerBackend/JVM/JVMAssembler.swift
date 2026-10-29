import Foundation

/// All branch targets are stack-neutral. Conditional branches use a short
/// inverted test over goto_w, so large methods never truncate branch offsets.
struct JVMAssembler {
    var code = JVMBytes()
    var labels: [Int: Int] = [:]
    var frames: Set<Int> = []
    var fixups: [(offset: Int, target: Int)] = []
    var shortFixups: [(offset: Int, target: Int)] = []
    private var nextInternalLabel = -1

    mutating func freshLabel() -> Int { defer { nextInternalLabel -= 1 }; return nextInternalLabel }
    mutating func mark(_ label: Int) {
        labels[label] = code.data.count
        frames.insert(code.data.count)
    }
    mutating func jump(_ label: Int) {
        let offset = code.data.count
        code.u1(0xC8); code.u4(0)
        fixups.append((offset, label))
    }
    mutating func branch(_ opcode: UInt8, to label: Int) throws {
        // if<cond> opcodes 0x99...0xA6 come in complementary pairs (ifeq/ifne, iflt/ifge, ...).
        guard (0x99...0xA6).contains(opcode) else { throw JVMEmissionError.limit("Unsupported JVM conditional opcode.") }
        let inverse: UInt8 = opcode & 1 == 1 ? opcode + 1 : opcode - 1
        code.u1(inverse); code.u2(8); jump(label)
        let skip = freshLabel(); mark(skip)
    }
    mutating func shortBranch(_ opcode: UInt8, to label: Int) {
        let offset = code.data.count
        code.u1(opcode); code.u2(0); shortFixups.append((offset, label))
    }
    mutating func finish() throws -> Data {
        guard code.data.count <= 65_535 else { throw JVMEmissionError.limit("JVM method bytecode exceeds 65535 bytes.") }
        for fixup in fixups {
            guard let target = labels[fixup.target], target < code.data.count else { throw JVMEmissionError.limit("JVM branch target is missing or outside method code.") }
            let delta = UInt32(bitPattern: Int32(target - fixup.offset))
            for index in 0..<4 { code.data[fixup.offset + 1 + index] = UInt8(truncatingIfNeeded: delta >> (24 - 8 * index)) }
        }
        for fixup in shortFixups {
            guard let target = labels[fixup.target], let delta = Int16(exactly: target - fixup.offset) else { throw JVMEmissionError.limit("JVM inline default expression exceeds the branch limit.") }
            let bits = UInt16(bitPattern: delta)
            code.data[fixup.offset + 1] = UInt8(truncatingIfNeeded: bits >> 8)
            code.data[fixup.offset + 2] = UInt8(truncatingIfNeeded: bits)
        }
        return code.data
    }
}
