import Foundation
import CompilerCore

/// Writes a classpath body cloned for concrete type arguments. The code keeps
/// the source class's constant pool indices; each `reifiedOperationMarker`
/// sequence is overwritten in place, padded with `nop` so no offset, branch
/// target or stack map frame moves.
enum JVMReifiedCloneEmitter {
    /// Operand room the patches may need beyond the original maximum stack.
    private static let extraStack: UInt16 = 3

    static func emit(_ clone: JVMReifiedClone, owner: String, pool: JVMConstantPool) throws -> JVMMethodCode {
        let analysis: JVMReifiedBody.Analysis
        do { analysis = try clone.body.analyze() } catch {
            throw JVMEmissionError.limit("Cannot read the reified classpath body for \(clone.name).")
        }
        var code = analysis.code.code
        for patch in clone.patches {
            var bytes = JVMBytes()
            try write(patch.operation, owner: owner, pool: pool, into: &bytes)
            let available = patch.end - patch.start
            guard bytes.data.count <= available, patch.start >= 0, patch.end <= code.count else {
                throw JVMEmissionError.limit("A reified patch for \(clone.name) does not fit its marker sequence.")
            }
            let replacement = Array(bytes.data) + Array(repeating: JVMBytecode.nop, count: available - bytes.data.count)
            code.replaceSubrange(patch.start..<patch.end, with: replacement)
        }
        guard code.count <= 65_535 else { throw JVMEmissionError.limit("Reified clone \(clone.name) exceeds the method size limit.") }
        var method = JVMMethodCode(
            name: try pool.utf8(clone.name), descriptor: try pool.utf8(clone.descriptor), access: 0x0009,
            code: Data(code), stack: analysis.code.maxStack &+ extraStack, locals: analysis.code.maxLocals,
            frames: analysis.code.stackMapTable
        )
        method.exceptions = analysis.code.exceptions.map { ($0.start, $0.end, $0.handler, $0.type) }
        return method
    }

    private static func write(_ operation: JVMReifiedClone.Operation, owner: String, pool: JVMConstantPool, into bytes: inout JVMBytes) throws {
        switch operation {
        case let .anewarray(name): bytes.u1(0xBD); bytes.u2(try pool.classInfo(name))
        case let .checkcast(name): bytes.u1(0xC0); bytes.u2(try pool.classInfo(name))
        case let .instanceOf(name): bytes.u1(0xC1); bytes.u2(try pool.classInfo(name))
        case let .ldcClass(name): bytes.u1(0x13); bytes.u2(try pool.classInfo(name))
        case let .checkcastNotNull(name, message):
            bytes.u1(0x13); bytes.u2(try pool.constant(.string(message)))
            bytes.u1(JVMBytecode.invokestatic)
            bytes.u2(try pool.member(10, owner: "java/util/Objects", name: "requireNonNull", descriptor: "(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;"))
            bytes.u1(0xC0); bytes.u2(try pool.classInfo(name))
        case let .helperCall(name, descriptor, cast):
            bytes.u1(JVMBytecode.invokestatic); bytes.u2(try pool.member(10, owner: owner, name: name, descriptor: descriptor))
            if let cast { bytes.u1(0xC0); bytes.u2(try pool.classInfo(cast)) }
        }
    }
}
