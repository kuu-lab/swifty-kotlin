import Foundation

extension JVMProgramBuilder {
    /// Only the initial return unboxes reference storage. Continuation workers
    /// continue to return logical boxes, including null-containing value classes.
    func lowerValueCoroutineReturns(_ input: JVMProgram) throws -> JVMProgram {
        var output = input
        func adapt(_ source: JVMFunction) -> JVMFunction {
            guard let representation = source.suspendValueResult, !source.isAbstract else { return source }
            var function = source, code: [JVMInstruction] = []
            var slot = source.locals.map { $0.slot + $0.type.width }.max() ?? 0
            var next = source.instructions.compactMap(\.labelNumber).max().map { $0 + 1 } ?? 0
            func value(_ type: JVMValueType) -> JVMValue { let v = JVMValue(slot: slot, type: type); slot += type.width; function.locals.append(v); return v }
            func label() -> Int { defer { next += 1 }; return next }
            let object: JVMValueType = .reference("java/lang/Object", nullable: true)
            let marker = value(object), check = value(.boolean), boxed = value(representation.boxed), raw = value(representation.underlying)
            let getMarker = JVMForeignMethod(owner: "kotlin/coroutines/intrinsics/IntrinsicsKt", name: "getCOROUTINE_SUSPENDED", descriptor: "()Ljava/lang/Object;", parameters: [], result: object, isStatic: true, isInterface: false, isAbstract: false)
            let unbox = JVMForeignMethod(owner: representation.boxed.referenceName!, name: "unbox-impl", descriptor: "()" + representation.underlying.descriptor, parameters: [], result: representation.underlying, isStatic: false, isInterface: false, isAbstract: false)
            for instruction in source.instructions {
                guard case let .returnValue(result?) = instruction else { code.append(instruction); continue }
                let convert = label()
                code += [.foreignCall(getMarker, receiver: nil, arguments: [], result: marker), .referenceCompare(.equal, result, marker, check), .jumpIfFalse(check, convert), .returnValue(result), .label(convert)]
                if representation.boxed.isNullable {
                    let nonnull = label(), null = value(object)
                    code += [.constant(.null, null), .referenceCompare(.equal, result, null, check), .jumpIfFalse(check, nonnull), .returnValue(result), .label(nonnull)]
                }
                code += [.copy(result, boxed), .foreignCall(unbox, receiver: boxed, arguments: [], result: raw), .returnValue(raw)]
            }
            function.instructions = code
            return function
        }
        output.functions = output.functions.map(adapt)
        for i in output.classes.indices { output.classes[i].functions = output.classes[i].functions.map(adapt) }
        return output
    }
}
