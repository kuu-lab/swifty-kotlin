import Foundation

extension JVMProgramBuilder {
    /// Nullable unsigned arrays are raw primitive arrays in typed code, but
    /// nullable Kotlin value-class boxes in erased calls and coroutine transport.
    /// Expand conversions after coroutine lowering so every entry path preserves null.
    func lowerUnsignedConversions(_ input: JVMProgram) throws -> JVMProgram {
        var output = input
        func transform(_ source: JVMFunction) throws -> JVMFunction {
            var f = source, code: [JVMInstruction] = []
            var slot = f.locals.map { $0.slot + $0.type.width }.max() ?? 0
            var next = f.instructions.compactMap(\.labelNumber).max().map { $0 + 1 } ?? 0
            func value(_ type: JVMValueType) -> JVMValue { let v = JVMValue(slot: slot, type: type); slot += type.width; f.locals.append(v); return v }
            func label() -> Int { defer { next += 1 }; return next }
            func nullableArray(_ type: JVMValueType) -> Bool { if case .unsignedArray(_, true) = type { return true }; return false }
            func convert(_ from: JVMValue, _ to: JVMValue) {
                if from.type != to.type, to.type.isNullable, from.type.referenceName != nil, to.type.referenceName != nil,
                   nullableArray(from.type) || nullableArray(to.type) {
                    let null = value(.reference("java/lang/Object", nullable: true)), check = value(.boolean), nonnull = label(), end = label()
                    code += [.constant(.null, null), .referenceCompare(.equal, from, null, check), .jumpIfFalse(check, nonnull), .constant(.null, to), .jump(end), .label(nonnull), .copy(from, to), .label(end)]
                } else { code.append(.copy(from, to)) }
            }
            for instruction in source.instructions {
                switch instruction {
                case let .copy(from, to): convert(from, to)
                case let .foreignCall(method, receiver, args, result?) where nullableArray(result.type) && (method.result != result.type || f.inlineContinuation != nil && method.isSuspend):
                    let raw = value(f.inlineContinuation != nil && method.isSuspend ? .reference("java/lang/Object", nullable: true) : method.result)
                    code.append(.foreignCall(method, receiver: receiver, arguments: args, result: raw)); convert(raw, result)
                case let .call(ref, args, result?) where nullableArray(result.type) && (ref.result != result.type || f.inlineContinuation != nil && ref.isSuspend):
                    let raw = value(f.inlineContinuation != nil && ref.isSuspend ? .reference("java/lang/Object", nullable: true) : ref.result); code.append(.call(ref, args, raw)); convert(raw, result)
                case let .arrayGet(array, index, result) where nullableArray(result.type):
                    let raw = value(JVMClasspathIndex.boxed(result.type))
                    code.append(.arrayGet(array, index, raw)); convert(raw, result)
                case let .arraySet(array, index, source) where nullableArray(source.type) && array.type.unsignedName == nil:
                    let boxed = value(JVMClasspathIndex.boxed(source.type)); convert(source, boxed)
                    code.append(.arraySet(array, index, boxed))
                case let .print(source?, newline) where nullableArray(source.type):
                    let boxed = value(.reference("java/lang/Object", nullable: true)); convert(source, boxed)
                    code.append(.print(boxed, newline: newline))
                case let .returnValue(source?) where f.inlineContinuation != nil && nullableArray(source.type):
                    let boxed = value(.reference("java/lang/Object", nullable: true)); convert(source, boxed); code.append(.returnValue(boxed))
                default: code.append(instruction)
                }
            }
            guard slot <= 65535 else { throw JVMFrontendError(message: "JVM unsigned conversion local slot limit exceeded.") }
            f.instructions = code
            return f
        }
        output.functions = try output.functions.map(transform)
        for i in output.classes.indices { output.classes[i].functions = try output.classes[i].functions.map(transform) }
        return output
    }
}
