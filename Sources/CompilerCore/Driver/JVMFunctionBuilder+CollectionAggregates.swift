import Foundation

extension JVMFunctionBuilder {
    func collectionAggregateMember(_ receiverID: ExprID, name: String, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        if name == "runningReduce" {
            guard args.count == 1, !args[0].isSpread,
                  let receiverType = program.sema.bindings.exprType(for: receiverID),
                  let owner = try program.type(receiverType).referenceName,
                  ["java/lang/Iterable", "java/util/Collection", "java/util/List", "java/util/Set", "java/util/ArrayList"].contains(owner),
                  !collectionCallIsExtension(id) else { return nil }
            return try iterableRunningReduce(receiverID, callback: args[0].expr, id: id)
        }
        guard ["sum", "average"].contains(name), args.isEmpty else { return nil }
        guard let receiverType = program.sema.bindings.exprType(for: receiverID),
              case let .classType(receiverClass) = program.sema.types.kind(of: receiverType),
              let argument = receiverClass.args.first,
              let owner = try program.type(receiverType).referenceName,
              ["java/lang/Iterable", "java/util/Collection", "java/util/List", "java/util/Set", "java/util/ArrayList"].contains(owner) else { return nil }

        // Some collection fallback calls have no CallBinding; the numeric
        // receiver still identifies the aggregate to lower.

        let element: TypeID
        switch argument {
        case let .invariant(type), let .out(type): element = type
        case .in, .star: return nil
        }
        guard program.sema.types.nullability(of: element) == .nonNull,
              case .primitive(_, .nonNull) = program.sema.types.kind(of: element) else { return nil }

        let elementType = try program.type(element)
        let average = name == "average"
        let accumulatorType: JVMValueType
        if average {
            guard [.byte, .short, .int, .long, .float, .double].contains(elementType) else { return nil }
            accumulatorType = .double
        } else {
            switch elementType {
            case .byte, .short, .int: accumulatorType = .int
            case .long, .float, .double, .ulong, .uint: accumulatorType = elementType
            case .ubyte, .ushort: accumulatorType = .uint
            default: return nil
            }
        }

        let collection = try convert(requireValue(receiverID), to: .reference(owner, nullable: false))
        let iteratorType: JVMValueType = .reference("java/util/Iterator", nullable: false)
        guard let iterator = try jdkCall("java/lang/Iterable", "iterator", [], iteratorType, receiver: collection, interface: true) else { return nil }
        let accumulator = try value(accumulatorType)
        instructions.append(.constant(average ? .double(0) : zeroConstant(for: accumulatorType), accumulator))
        let count = average ? try constant(.int(0), .int) : nil
        let loop = label(), end = label()
        mark(loop)
        guard let hasNext = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true) else { return nil }
        instructions.append(.jumpIfFalse(hasNext, end))
        guard let boxedElement = try jdkCall(
            "java/util/Iterator", "next", [], .reference("java/lang/Object", nullable: true),
            receiver: iterator, interface: true
        ) else { return nil }
        let rawValue = try aggregateElement(boxedElement, type: elementType)
        let term = try convert(rawValue, to: accumulatorType)
        let next = try value(accumulatorType)
        instructions.append(.binary(.add, accumulator, term, next))
        instructions.append(.copy(next, accumulator))
        if let count {
            let incremented = try value(.int)
            instructions.append(.binary(.add, count, try constant(.int(1), .int), incremented))
            instructions.append(.copy(incremented, count))
        }
        jump(loop)
        mark(end)

        if let count {
            let result = try value(.double)
            let isEmpty = try value(.boolean)
            instructions.append(.binary(.equal, count, try constant(.int(0), .int), isEmpty))
            let divide = label(), done = label()
            instructions.append(.jumpIfFalse(isEmpty, divide))
            instructions.append(.constant(.double(.nan), result))
            jump(done)
            mark(divide)
            let divisor = try convert(count, to: .double)
            let average = try value(.double)
            instructions.append(.binary(.divide, accumulator, divisor, average))
            instructions.append(.copy(average, result))
            mark(done)
            return JVMIntrinsicResult(value: try convert(result, to: program.expressionType(id)))
        }
        return JVMIntrinsicResult(value: try convert(accumulator, to: program.expressionType(id)))
    }

    private func iterableRunningReduce(_ receiverID: ExprID, callback: ExprID, id: ExprID) throws -> JVMIntrinsicResult {
        guard let signature = functionType(callback), signature.params.count == 2 else {
            throw fail("JVM Iterable runningReduce requires a two-argument callback.", id)
        }
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let iterableType = JVMValueType.reference("java/lang/Iterable", nullable: false)
        let iterable = try convert(requireValue(receiverID), to: iterableType)
        let operation = try requireValue(callback)
        let iterator = try jdkCall(
            "java/lang/Iterable", "iterator", [],
            .reference("java/util/Iterator", nullable: false),
            receiver: iterable,
            interface: true
        )!
        let resultType = try program.expressionType(id)
        let result = try value(resultType)
        let accumulatorType = try program.type(signature.params[0])
        let accumulator = try value(accumulatorType)
        let hasFirst = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true)!
        let empty = label(), loop = label(), finished = label(), done = label()
        instructions.append(.jumpIfFalse(hasFirst, empty))

        let first = try jdkCall("java/util/Iterator", "next", [], object, receiver: iterator, interface: true)!
        instructions.append(.copy(try convert(first, to: accumulatorType), accumulator))
        let values = try constructJDK("java/util/ArrayList")
        _ = try jdkCall("java/util/ArrayList", "add", [object], .boolean, receiver: values, arguments: [accumulator])
        jump(loop)

        mark(loop)
        let hasNext = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true)!
        instructions.append(.jumpIfFalse(hasNext, finished))
        let element = try jdkCall("java/util/Iterator", "next", [], object, receiver: iterator, interface: true)!
        guard let next = try invoke(operation, signature: signature, arguments: [accumulator, element], resultType: accumulatorType) else {
            throw fail("JVM Iterable runningReduce callback must return a value.", id)
        }
        instructions.append(.copy(try convert(next, to: accumulatorType), accumulator))
        _ = try jdkCall("java/util/ArrayList", "add", [object], .boolean, receiver: values, arguments: [accumulator])
        jump(loop)

        mark(finished)
        instructions.append(.copy(try convert(values, to: resultType), result))
        jump(done)

        mark(empty)
        guard let emptyValues = try jdkCall(
            "java/util/Collections", "emptyList", [],
            .reference("java/util/List", nullable: false),
            resolved: resultType
        ) else { throw fail("JVM Iterable runningReduce could not produce an empty list.", id) }
        instructions.append(.copy(emptyValues, result))
        mark(done)
        return JVMIntrinsicResult(value: result)
    }

    private func aggregateElement(_ source: JVMValue, type: JVMValueType) throws -> JVMValue {
        if let unsignedOwner = type.unsignedName {
            let boxed = try convert(source, to: .reference(unsignedOwner, nullable: false))
            guard let value = try jdkCall(unsignedOwner, "unbox-impl", [], type, receiver: boxed) else {
                throw fail("JVM unsigned collection aggregate did not produce a value.")
            }
            return value
        }
        let method: String
        switch type {
        case .byte: method = "byteValue"
        case .short: method = "shortValue"
        case .int: method = "intValue"
        case .long: method = "longValue"
        case .float: method = "floatValue"
        case .double: method = "doubleValue"
        default: throw fail("Unsupported JVM numeric collection element.")
        }
        let number = try convert(source, to: .reference("java/lang/Number", nullable: false))
        guard let value = try jdkCall("java/lang/Number", method, [], type, receiver: number) else {
            throw fail("JVM collection aggregate conversion did not produce a value.")
        }
        return value
    }

    private func zeroConstant(for type: JVMValueType) -> JVMConstant {
        switch type {
        case .long, .ulong: .long(0)
        case .float: .float(0)
        case .double: .double(0)
        default: .int(0)
        }
    }
}
