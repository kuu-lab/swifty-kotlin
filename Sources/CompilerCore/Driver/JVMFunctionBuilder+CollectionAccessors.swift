import Foundation

extension JVMFunctionBuilder {
    func collectionDefaultValueMember(
        _ receiverID: ExprID,
        owner: String,
        member: String,
        args: [CallArgument],
        id: ExprID
    ) throws -> JVMIntrinsicResult {
        let isList = owner == "java/util/List"
        guard args.count == 2, args.allSatisfy({ !$0.isSpread }) else {
            throw fail("Unsupported JVM collection default-value arguments.", id)
        }
        if member == "getOrPut" {
            try requireMutableCollection(receiverID, at: id)
            try requireWritableArguments(receiverID, at: id)
        }

        var supplied: [Int: (ExprID, JVMValue)] = [:]
        let binding = program.sema.bindings.callBinding(for: id)
        for (position, argument) in args.enumerated() {
            let label = argument.label.map(context.interner.resolve)
            let fallbackIndex = label.map { name in
                if ["index", "key"].contains(name) { return 0 }
                if name == "defaultValue" { return 1 }
                return position
            }
            let parameterIndex = binding?.parameterMapping[position] ?? fallbackIndex ?? position
            guard (0..<2).contains(parameterIndex), supplied[parameterIndex] == nil else {
                throw fail("Invalid JVM collection default-value argument mapping.", id)
            }
            supplied[parameterIndex] = (argument.expr, try requireValue(argument.expr))
        }
        guard let key = supplied[0]?.1,
              let defaultEntry = supplied[1],
              let signature = functionType(defaultEntry.0),
              signature.params.count == (isList ? 1 : 0)
        else { throw fail("JVM collection default value requires a matching function.", id) }

        let resultType = try program.expressionType(id)
        let result = try value(resultType)
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let receiverType = try convert(
            requireValue(receiverID),
            to: .reference(owner, nullable: false)
        )
        if isList {
            let index = try convert(key, to: .int)
            let size = try jdkCall(owner, "size", [], .int, receiver: receiverType, interface: true)!
            let fallback = label(), end = label()
            let nonnegative = try value(.boolean)
            instructions.append(.binary(.greaterOrEqual, index, try constant(.int(0), .int), nonnegative))
            instructions.append(.jumpIfFalse(nonnegative, fallback))
            let inBounds = try value(.boolean)
            instructions.append(.binary(.lessThan, index, size, inBounds))
            instructions.append(.jumpIfFalse(inBounds, fallback))
            let existing = try jdkCall(owner, "get", [.int], object, receiver: receiverType, arguments: [index], interface: true)!
            instructions.append(.copy(try convert(existing, to: resultType), result))
            jump(end)
            mark(fallback)
            let defaultValue = try invoke(defaultEntry.1, signature: signature, arguments: [index], resultType: resultType)!
            instructions.append(.copy(try convert(defaultValue, to: resultType), result))
            mark(end)
        } else {
            let current = try jdkCall("java/util/Map", "get", [object], object, receiver: receiverType, arguments: [key], interface: true)!
            let missing = try value(.boolean)
            instructions.append(.referenceCompare(.equal, current, try constant(.null, object), missing))
            let fallback = label(), present = label(), end = label()
            instructions.append(.jumpIfFalse(missing, present))
            jump(fallback)
            mark(present)
            instructions.append(.copy(try convert(current, to: resultType), result))
            jump(end)
            mark(fallback)
            let value = try invoke(defaultEntry.1, signature: signature, arguments: [], resultType: resultType)!
            if member == "getOrPut" {
                _ = try jdkCall("java/util/Map", "put", [object, object], object, receiver: receiverType, arguments: [key, value], interface: true)
            }
            instructions.append(.copy(try convert(value, to: resultType), result))
            mark(end)
        }
        return JVMIntrinsicResult(value: result)
    }
}
