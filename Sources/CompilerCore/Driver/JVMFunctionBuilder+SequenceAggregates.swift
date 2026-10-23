import Foundation

extension JVMFunctionBuilder {
    func sequenceAggregate(_ receiverID: ExprID, member: String, id: ExprID) throws -> JVMValue {
        guard let receiverType = program.sema.bindings.exprType(for: receiverID),
              case let .classType(classType) = program.sema.types.kind(of: receiverType),
              let argument = classType.args.first
        else {
            throw fail("JVM Sequence aggregate requires a numeric element type.", id)
        }
        let elementType: TypeID
        switch argument {
        case let .invariant(type), let .out(type), let .in(type): elementType = type
        case .star: throw fail("JVM Sequence aggregate requires a numeric element type.", id)
        }
        let element = try program.type(elementType)
        guard element.isNumeric else { throw fail("JVM Sequence aggregate requires a numeric element type.", id) }

        let resultType = try program.expressionType(id)
        let sumType: JVMValueType = member == "average" ? .double : resultType
        let sequence = try convert(
            requireValue(receiverID),
            to: .reference("kotlin/sequences/Sequence", nullable: false)
        )
        let iterator = try jdkCall(
            "kotlin/sequences/Sequence", "iterator", [],
            .reference("java/util/Iterator", nullable: false),
            receiver: sequence, interface: true
        )!
        let sum = try zero(sumType)
        let count = member == "average" ? try zero(.int) : nil
        let test = label(), end = label()
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        mark(test)
        let hasNext = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true)!
        instructions.append(.jumpIfFalse(hasNext, end))
        let item = try jdkCall("java/util/Iterator", "next", [], object, receiver: iterator, interface: true)!
        let unboxed = try convert(item, to: element)
        let number = try convert(unboxed, to: member == "average" ? .double : sumType)
        let nextSum = try value(sumType)
        instructions.append(.binary(.add, sum, number, nextSum))
        instructions.append(.copy(nextSum, sum))
        if let count {
            let nextCount = try value(.int)
            instructions.append(.binary(.add, count, try constant(.int(1), .int), nextCount))
            instructions.append(.copy(nextCount, count))
        }
        jump(test)
        mark(end)

        guard member == "average", let count else { return try convert(sum, to: resultType) }
        let result = try value(resultType)
        let empty = try value(.boolean)
        instructions.append(.binary(.equal, count, try constant(.int(0), .int), empty))
        let divide = label(), merge = label()
        instructions.append(.jumpIfFalse(empty, divide))
        instructions.append(.constant(.double(.nan), result))
        jump(merge)
        mark(divide)
        let denominator = try convert(count, to: .double)
        instructions.append(.binary(.divide, sum, denominator, result))
        mark(merge)
        return result
    }
}
