extension JVMFunctionBuilder {
    func compoundInstruction(_ op: BinaryOp, _ left: JVMValue, _ right: JVMValue, _ result: JVMValue) throws {
        if op == .add && result.type.isText {
            instructions.append(.copy(try convert(concatenate(left, right), to: result.type), result)); return
        }
        let type = try numericType(left.type, right.type)
        instructions.append(.binary(op, try convert(left, to: type), try convert(right, to: type), result))
    }
    func permitsCompound(_ target: JVMValueType, _ argument: JVMValueType) throws -> Bool {
        if target.isText { return true }
        if [.byte, .short, .char, .ubyte, .ushort].contains(target), argument.stackType == .int { return true }
        return try numericType(target, argument) == target
    }
    func numericType(_ a: JVMValueType, _ b: JVMValueType) throws -> JVMValueType {
        guard let a = a.numericCarrier, let b = b.numericCarrier else { throw fail("JVM arithmetic/comparison requires numeric operands.") }
        if a == .char && b == .char { return .char }
        if a.unsignedName != nil || b.unsignedName != nil { return a == .ulong || b == .ulong ? .ulong : .uint }
        return [.double, .float, .long].first { $0 == a || $0 == b } ?? .int
    }

    func binary(_ op: BinaryOp, _ lhs: ExprID, _ rhs: ExprID, _ id: ExprID) throws -> JVMValue? {
        if op == .rangeTo {
            if let symbol = program.sema.bindings.callBinding(for: id)?.chosenCallee,
               program.inlineDeclarations[symbol] != nil || program.references[symbol] != nil || program.methods[symbol] != nil {
                let args = [CallArgument(expr: rhs)]
                if let call = try inlineCall(args, receiver: lhs, id: id)
                    ?? sourceCall(args, receiver: lhs, id: id) { return call.value }
            }
            let lower = try requireValue(lhs), upper = try requireValue(rhs)
            if lower.type == .double, upper.type == .double {
                // Kotlin's concrete floating range classes are package-private;
                // construct them through the public stdlib facade.
                return try jdkCall(
                    "kotlin/ranges/RangesKt", "rangeTo", [.double, .double],
                    .reference("kotlin/ranges/ClosedFloatingPointRange", nullable: false),
                    arguments: [lower, upper]
                )
            }
            if lower.type == .float, upper.type == .float {
                return try jdkCall(
                    "kotlin/ranges/RangesKt", "rangeTo", [.float, .float],
                    .reference("kotlin/ranges/ClosedFloatingPointRange", nullable: false),
                    arguments: [lower, upper]
                )
            }
            let rangeType = try program.expressionType(id)
            let rangeClass: String
            let elementType: JVMValueType
            switch rangeType.referenceName {
            case "kotlin/ranges/IntRange":
                rangeClass = "kotlin/ranges/IntRange"
                elementType = .int
            case "kotlin/ranges/LongRange":
                rangeClass = "kotlin/ranges/LongRange"
                elementType = .long
            case "kotlin/ranges/CharRange":
                rangeClass = "kotlin/ranges/CharRange"
                elementType = .char
            default:
                throw fail("JVM range expressions currently support IntRange, LongRange, CharRange, and floating-point ranges.", id)
            }
            return try constructJDK(
                rangeClass,
                parameters: [elementType, elementType],
                arguments: [try convert(lower, to: elementType), try convert(upper, to: elementType)]
            )
        }
        if op == .downTo {
            let first = try requireValue(lhs), last = try requireValue(rhs)
            guard first.type == .int, last.type == .int else {
                throw fail("JVM downTo expressions currently require Int operands.", id)
            }
            // The range marker maps Int-backed expressions to IntRange, but
            // downTo returns IntProgression. Its factory is on the companion.
            let progression: JVMValueType = .reference("kotlin/ranges/IntProgression", nullable: false)
            let companionType: JVMValueType = .reference("kotlin/ranges/IntProgression$Companion", nullable: false)
            let companion = try value(companionType)
            instructions.append(.getStatic(
                JVMField(owner: "kotlin/ranges/IntProgression", name: "Companion", type: companionType, access: 0x19),
                companion
            ))
            return try jdkCall(
                "kotlin/ranges/IntProgression$Companion",
                "fromClosedRange",
                [.int, .int, .int],
                progression,
                receiver: companion,
                arguments: [first, last, try constant(.int(-1), .int)]
            )
        }
        if [.add, .subtract, .multiply, .divide, .modulo].contains(op) {
            let args = [CallArgument(expr: rhs)]
            if let call = try inlineCall(args, receiver: lhs, id: id)
                ?? sourceCall(args, receiver: lhs, id: id) { return call.value }
            if let call = try textLibraryCall(args, receiver: lhs, id: id) { return call.value }
        }
        let ordering = [BinaryOp.lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual].contains(op)
        if ordering {
            let args = [CallArgument(expr: rhs)]
            if let call = try inlineCall(args, receiver: lhs, id: id, expectedResult: .int)
                ?? sourceCall(args, receiver: lhs, id: id, expectedResult: .int), let compared = call.value {
                let result = try value(.boolean)
                instructions.append(.binary(op, compared, try constant(.int(0), .int), result)); return result
            }
        }
        let left = try requireValue(lhs)
        if op == .elvis {
            let type = try program.expressionType(id), result = try value(type), fallback = label(), end = label()
            guard left.type.referenceName != nil else { throw fail("JVM elvis requires a nullable reference or boxed primitive.", id) }
            let null = try constant(.null, .reference("java/lang/Object", nullable: true)), check = try value(.boolean)
            instructions.append(.referenceCompare(.notEqual, left, null, check)); instructions.append(.jumpIfFalse(check, fallback))
            instructions.append(.copy(try convert(left, to: type), result)); jump(end)
            mark(fallback)
            let right = try expression(rhs)
            if !terminated {
                guard let right else { throw fail("JVM elvis fallback must produce a value.", id) }
                instructions.append(.copy(try convert(right, to: type), result))
            }
            mark(end); return result
        }
        if op == .logicalAnd || op == .logicalOr {
            guard left.type == .boolean else { throw fail("JVM logical operators require Boolean operands.", id) }
            let result = try value(.boolean), short = label(), end = label()
            if op == .logicalAnd { instructions.append(.jumpIfFalse(left, short)) }
            else {
                let negated = try value(.boolean)
                instructions.append(.unary(.not, left, negated)); instructions.append(.jumpIfFalse(negated, short))
            }
            let right = try expression(rhs)
            if !terminated {
                guard let right, right.type == .boolean else { throw fail("JVM logical operators require Boolean operands.", id) }
                instructions.append(.copy(right, result)); jump(end)
            }
            mark(short); instructions.append(.constant(.boolean(op == .logicalOr), result)); mark(end)
            return result
        }
        if op == .add, left.type.referenceName == "java/lang/String" || left.type == .char, try program.expressionType(id) == .string {
            guard let right = try stringPart(rhs) else { return try value(.string) }
            return try concatenate(left, right)
        }
        let right = try requireValue(rhs)
        if ordering, left.type.isText, right.type.isText {
            let compared = try jdkCall("java/lang/String", "compareTo", [.string], .int, receiver: convert(left, to: .string), arguments: [right])!
            let result = try value(.boolean); instructions.append(.binary(op, compared, try constant(.int(0), .int), result)); return result
        }
        if ordering, left.type.numericCarrier == nil, right.type.numericCarrier == nil,
           let binding = program.sema.bindings.callBinding(for: id),
           let method = program.textLibraryMethods[binding.chosenCallee]?.method,
           method.owner == "java/lang/Comparable", method.name == "compareTo" {
            let compared = try jdkCall(method.owner, method.name, method.parameters, .int, receiver: left, arguments: [right], interface: true)!
            let result = try value(.boolean)
            instructions.append(.binary(op, compared, try constant(.int(0), .int), result)); return result
        }
        if op == .identityEqual || op == .notIdentityEqual {
            guard left.type.referenceName != nil, right.type.referenceName != nil else { throw fail("JVM identity comparison requires reference operands.", id) }
            let result = try value(.boolean)
            instructions.append(.referenceCompare(op == .identityEqual ? .equal : .notEqual, left, right, result)); return result
        }
        if [.equal, .notEqual].contains(op), let result = try nullableFloatingEquality(op, left, right) { return result }
        let comparison = [BinaryOp.equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual].contains(op)
        guard comparison || [BinaryOp.add, .subtract, .multiply, .divide, .modulo, .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr].contains(op) else { throw fail("Unsupported JVM binary operator.", id) }
        if comparison, [.equal, .notEqual].contains(op), left.type == right.type,
           left.type == .boolean || left.type == .string {
            let result = try value(.boolean)
            instructions.append(.binary(op, left, right, result)); return result
        }
        if [.equal, .notEqual].contains(op), left.type.referenceName != nil, right.type.referenceName != nil {
            // Equality against a null literal never dispatches to equals.
            if case .nullLiteral = arena.expr(lhs) {
                let result = try value(.boolean); instructions.append(.referenceCompare(op, left, right, result)); return result
            }
            if case .nullLiteral = arena.expr(rhs) {
                let result = try value(.boolean); instructions.append(.referenceCompare(op, left, right, result)); return result
            }
            let result = try value(.boolean)
            instructions.append(.binary(op, left, right, result)); return result
        }
        if [.equal, .notEqual].contains(op), left.type.referenceName != nil || right.type.referenceName != nil {
            let any: JVMValueType = .reference("java/lang/Object", nullable: true)
            let a = try convert(left, to: any), b = try convert(right, to: any), result = try value(.boolean)
            instructions.append(.binary(op, a, b, result)); return result
        }
        let promoted = try numericType(left.type, right.type)
        // Arithmetic uses operand width before a contextual result widening.
        // Char comparisons retain Char, while Char subtraction produces Int.
        let type: JVMValueType = !comparison && promoted == .char ? .int : promoted
        let a = try convert(left, to: type), b = try convert(right, to: [.shl, .shr, .ushr].contains(op) ? .int : type)
        let result = try value(comparison ? .boolean : type)
        instructions.append(.binary(op, a, b, result))
        return try comparison ? result : convert(result, to: program.expressionType(id))
    }

    func conditional(_ id: ExprID, _ condition: ExprID, _ thenExpr: ExprID, _ elseExpr: ExprID?, discarded: Bool = false) throws -> JVMValue? {
        let check = try requireValue(condition)
        guard check.type == .boolean else { throw fail("JVM if condition must be Boolean.", id) }
        let type = try program.expressionType(id)
        let result = discarded || type == .unit ? nil : try value(type)
        let alternate = label(), end = label()
        instructions.append(.jumpIfFalse(check, alternate))
        let yes = try expression(thenExpr, discarded: discarded)
        let yesTerminated = terminated
        if !yesTerminated {
            if let result {
                guard let yes else { throw fail("JVM if branch must produce a value.", id) }
                instructions.append(.copy(try convert(yes, to: type), result))
            }
            jump(end)
        }
        mark(alternate)
        let no = try elseExpr.flatMap { try expression($0, discarded: discarded) }
        let noTerminated = terminated
        if !noTerminated, let result {
            guard let no else { throw fail("JVM value-producing if requires else and two values.", id) }
            instructions.append(.copy(try convert(no, to: type), result))
        }
        if yesTerminated && noTerminated { terminated = true }
        else { mark(end) }
        return result
    }

    func forLoop(
        _ name: InternedString?,
        _ iterable: ExprID,
        _ body: ExprID,
        _ id: ExprID,
        destructuringNames: [InternedString?]? = nil,
        label loopLabel: InternedString? = nil
    ) throws {
        let loopName = name ?? context.interner.intern("__jvm_for_destructuring_\(id.rawValue)")
        if let destructuringNames {
            guard loopLabel == nil else { throw fail("JVM loop labels are not supported.", id) }
            try sequenceLoop(loopName, iterable, body, id, destructuringNames: destructuringNames)
            return
        }
        if case let .binary(op, _, _, _) = arena.expr(iterable), op == .rangeTo,
           program.hasSourceRangeOperator(iterable) {
            try sequenceLoop(loopName, iterable, body, id, label: loopLabel)
            return
        }
        let range: (BinaryOp, ExprID, ExprID)? = switch arena.expr(iterable) {
        case let .binary(op, from, to, _) where [BinaryOp.rangeTo, .rangeUntil, .downTo].contains(op):
            (op, from, to)
        case let .memberCall(receiver, callee, _, args, _)
            where context.interner.resolve(callee) == "until" && args.count == 1 &&
                (try? program.expressionType(iterable).referenceName) == "kotlin/ranges/IntRange":
            (.rangeUntil, receiver, args[0].expr)
        default:
            nil
        }
        guard let (op, from, to) = range else {
            try sequenceLoop(loopName, iterable, body, id, label: loopLabel); return
        }
        let first = try requireValue(from), last = try requireValue(to)
        let type = try numericType(first.type, last.type)
        guard type.stackType == .int || type.stackType == .long else { throw fail("JVM for ranges require integral operands.", id) }
        let induction = try value(type), bound = try value(type)
        instructions.append(.copy(try convert(first, to: type), induction))
        instructions.append(.copy(try convert(last, to: type), bound))
        scopes.append([loopName: Local(value: induction, mutable: false)])
        defer { scopes.removeLast() }
        let test = label(), advance = label(), exit = label()
        mark(test)
        let check = try value(.boolean)
        let comparison: BinaryOp = op == .rangeUntil ? .lessThan : (op == .downTo ? .greaterOrEqual : .lessOrEqual)
        instructions.append(.binary(comparison, induction, bound, check))
        instructions.append(.jumpIfFalse(check, exit))
        loops.append(LoopFrame(label: loopLabel, exit: exit, next: advance, allocationDepth: pendingAllocations.count)); _ = try expression(body, discarded: true); loops.removeLast()
        mark(advance)
        // Test the inclusive terminal element before incrementing. This keeps
        // MAX_VALUE/MIN_VALUE ranges finite even when the next value overflows.
        if op != .rangeUntil {
            let more = try value(.boolean)
            instructions.append(.binary(.notEqual, induction, bound, more))
            instructions.append(.jumpIfFalse(more, exit))
        }
        let one = try constant(type.width == 1 ? .int(1) : .long(1), type)
        let next = try value(type)
        instructions.append(.binary(op == .downTo ? .subtract : .add, induction, one, next))
        instructions.append(.copy(next, induction)); jump(test); mark(exit)
    }
}

extension JVMFunctionBuilder {
    /// Statically floating-point nullable operands retain IEEE equality;
    /// values erased to Any continue to use wrapper/Object equality.
    func nullableFloatingEquality(_ op: BinaryOp, _ left: JVMValue, _ right: JVMValue) throws -> JVMValue? {
        let floating: [(JVMValueType, String)] = [(.float, "java/lang/Float"), (.double, "java/lang/Double")]
        guard let (primitive, wrapper) = floating.first(where: { primitive, wrapper in
            (left.type == primitive || left.type.referenceName == wrapper) &&
            (right.type == primitive || right.type.referenceName == wrapper) &&
            (left.type.referenceName != nil || right.type.referenceName != nil)
        }) else { return nil }
        _ = wrapper
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let a = try convert(left, to: object), b = try convert(right, to: object)
        let null = try constant(.null, object), checkA = try value(.boolean), checkB = try value(.boolean)
        let result = try value(.boolean), nullCase = label(), end = label()
        instructions.append(.referenceCompare(.notEqual, a, null, checkA)); instructions.append(.jumpIfFalse(checkA, nullCase))
        instructions.append(.referenceCompare(.notEqual, b, null, checkB)); instructions.append(.jumpIfFalse(checkB, nullCase))
        let x = try convert(a, to: primitive), y = try convert(b, to: primitive)
        instructions.append(.binary(.equal, x, y, result)); jump(end)
        mark(nullCase); instructions.append(.binary(.equal, a, b, result)); mark(end)
        if op == .notEqual { instructions.append(.unary(.not, result, result)) }
        return result
    }
}
