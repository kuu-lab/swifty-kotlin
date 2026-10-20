extension JVMProgramBuilder {
    /// Unlowered bytecode consumed by Kotlin's coroutine-aware bytecode inliner.
    func inlineSuspendBody(_ source: JVMFunction, exported: Bool) -> JVMFunction {
        var body = source
        let params = Array(source.locals.prefix(source.parameterCount))
        let slot = params.map { $0.slot + $0.type.width }.max() ?? 0
        let continuation = JVMValue(slot: slot, type: .reference("kotlin/coroutines/Continuation", nullable: false))
        func shift(_ value: JVMValue) -> JVMValue { JVMValue(slot: value.slot >= slot ? value.slot + 1 : value.slot, type: value.type) }
        body.locals = params + [continuation] + source.locals.dropFirst(source.parameterCount).map(shift)
        body.instructions = source.instructions.map { $0.mappingValues(shift) }
        body.parameterCount += 1
        body.inlineContinuation = continuation
        body.reference = source.reference.suspendABI
        if !exported {
            body.reference = JVMFunctionReference(name: source.reference.name + "$$forInline", parameters: body.reference.parameters, result: body.reference.result, owner: source.reference.owner, ownerIsInterface: source.reference.ownerIsInterface)
            body.access = ((source.access ?? 9) & 8) | 2 | 0x1000
            body.isPrivate = true; body.isSynthetic = true
        }
        if let signature = source.genericSignature, let end = signature.lastIndex(of: ")") {
            let logical = String(signature[signature.index(after: end)...])
            let boxed: [String: String] = ["V": "Lkotlin/Unit;", "B": "Ljava/lang/Byte;", "S": "Ljava/lang/Short;", "C": "Ljava/lang/Character;", "I": "Ljava/lang/Integer;", "J": "Ljava/lang/Long;", "F": "Ljava/lang/Float;", "D": "Ljava/lang/Double;", "Z": "Ljava/lang/Boolean;"]
            let unsignedNames = ["UInt", "ULong", "UByte", "UShort"].flatMap { ["kotlin/" + $0, "kotlin/" + $0 + "Array"] }
            let unsigned: String?
            if case let .named(name, _, _) = source.kotlinResult, unsignedNames.contains(name) { unsigned = "L" + name + ";" } else { unsigned = nil }
            body.genericSignature = String(signature[..<end]) + "Lkotlin/coroutines/Continuation<-" + (unsigned ?? boxed[logical] ?? logical) + ">;)Ljava/lang/Object;"
        }
        return body
    }
}

extension JVMProgramBuilder {
    /// Null-safe conversions used by the coroutine inliner's boxed resume path.
    func nullableInlineSuspendAdapters(_ representation: JVMSuspendValueResult) -> [JVMFunction] {
        let name = representation.boxed.referenceName!, owner = representation.adapterOwner ?? representation.boxed.referenceName!, object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let input = JVMValue(slot: 0, type: object), check = JVMValue(slot: 1, type: .boolean), null = JVMValue(slot: 2, type: representation.boxed)
        let box = JVMValue(slot: 3, type: representation.boxed), raw = JVMValue(slot: 4, type: representation.underlying)
        let prefix: [JVMInstruction] = [.constant(.null, null), .referenceCompare(.equal, input, null, check), .jumpIfFalse(check, 0), .returnValue(null), .label(0)]
        let unbox = JVMForeignMethod(owner: name, name: "unbox-impl", descriptor: "()" + raw.type.descriptor, parameters: [], result: raw.type, isStatic: false, isInterface: false, isAbstract: false)
        let boxing = JVMForeignMethod(owner: name, name: "box-impl", descriptor: "(" + raw.type.descriptor + ")L" + name + ";", parameters: [raw.type], result: box.type, isStatic: true, isInterface: false, isAbstract: false)
        return [
            rawFunction(owner, name: "$unboxSuspend$inline", parameters: [object], result: object, access: 0x1009, locals: [input, check, null, box, raw], instructions: prefix + [.copy(input, box), .foreignCall(unbox, receiver: box, arguments: [], result: raw), .returnValue(raw)]),
            rawFunction(owner, name: "$boxSuspend$inline", parameters: [object], result: box.type, access: 0x1009, locals: [input, check, null, box, raw], instructions: prefix + [.copy(input, raw), .foreignCall(boxing, receiver: nil, arguments: [raw], result: box), .returnValue(box)])
        ]
    }
}
