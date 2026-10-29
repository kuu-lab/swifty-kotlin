import Foundation

/// Result of an in-process KIR execution attempt (`kswiftc --run`).
public enum KIRInterpreterOutcome: Equatable, Sendable {
    /// The program ran to completion inside the interpreter; `stdout` is
    /// everything it printed (buffered so a late bail-out stays side-effect free).
    case completed(stdout: String)
    /// The program uses something the interpreter does not model. Nothing was
    /// observable; the caller must compile and run it natively instead.
    case fallback(reason: String)
}

/// Tree-walking interpreter over lowered KIR. It exists for the edit→run dev
/// loop: it skips Codegen + Link entirely, but only models a deliberately small
/// "pure logic" subset (Int/Boolean/String values, control flow, calls between
/// user functions, console output). Everything else is reported through
/// `.fallback`, decided in two layers:
///
/// 1. a static scan of every function reachable from the entry point
///    (unsupported instruction / callee / global ⇒ fallback before running);
/// 2. runtime bail-outs for conditions that depend on values (division by
///    zero, call depth). Output is buffered, so a runtime bail-out also leaves
///    no trace and the native path re-runs the program from scratch.
///
/// Runtime calls are executed by a small table that mirrors the semantics of
/// the native runtime / emitter for the same `kk_*` names (all values are
/// 64-bit words there, boxing is the identity here).
public enum KIRInterpreter {
    public static func run(context ctx: CompilationContext) -> KIRInterpreterOutcome {
        guard let kir = ctx.kir, let ast = ctx.ast, let sema = ctx.sema else {
            return .fallback(reason: "frontend state unavailable")
        }
        guard let entry = ExecutableEntryPointSelector.firstFileLevelSymbol(
            ast: ast, bindings: sema.bindings, arena: kir.arena, interner: ctx.interner,
            symbols: sema.symbols, entryPointFQName: ctx.options.entryPointFQName
        ) else {
            return .fallback(reason: "no entry point")
        }
        let engine = KIRInterpreterEngine(kir: kir, sema: sema, interner: ctx.interner)
        let box = KIRInterpreterEngineBox(engine)
        // Interpreter frames recurse on the Swift stack; run on a large one.
        let outcome = try? LargeStackExecutor.run { box.engine.execute(entry: entry) }
        return outcome ?? .fallback(reason: "interpreter failed to start")
    }
}

private final class KIRInterpreterEngineBox: @unchecked Sendable {
    let engine: KIRInterpreterEngine
    init(_ engine: KIRInterpreterEngine) { self.engine = engine }
}

private enum IValue: Equatable {
    case int(Int64)
    case string(String)
    case unit
    /// Kotlin `null` is its own value, not a bit pattern inside `.int`: the
    /// native null sentinel (Int64.min) is a legitimate Long/ULong/Double
    /// payload, so a sentinel would stringify and compare real values as
    /// "null" (KUU-3687).
    case null
}

private struct InterpreterBail: Error {
    let reason: String
}

private final class KIRInterpreterEngine {
    private static let maxCallDepth = 5000

    /// Callees that mirror a native runtime/emitter operation on plain words.
    private static let supportedBuiltins: Set<String> = [
        "kk_unbox_int_static", "kk_unbox_bool_static", "kk_unbox_long_static",
        "kk_box_int", "kk_box_bool", "kk_box_long", "kk_box_long_nonnull",
        "kk_box_int_static", "kk_box_bool_static", "kk_box_long_static",
        "kk_box_long_nonnull_static", "kk_box_byte_static", "kk_box_short_static",
        "kk_unbox_int", "kk_unbox_bool", "kk_unbox_long",
        "kk_int_narrow", "kk_uint_narrow",
        "kk_op_add", "kk_op_sub", "kk_op_mul", "kk_op_div", "kk_op_mod", "kk_op_rem",
        "kk_op_eq", "kk_op_ne", "kk_op_lt", "kk_op_le", "kk_op_gt", "kk_op_ge",
        "kk_double_equals", "kk_float_equals",
        "kk_nullable_double_equals", "kk_nullable_float_equals",
        "kk_nullable_primitive_eq", "kk_nullable_primitive_ne",
        "kk_op_and", "kk_op_or", "kk_op_not",
        "kk_bitwise_and", "kk_bitwise_or", "kk_bitwise_xor",
        "kk_op_ishl", "kk_op_ishr",
        "__kk_int_range_induction_le", "__kk_int_range_induction_add",
        "__kk_string_concat_flat", "kk_any_to_string",
        "__kk_print_raw", "__kk_println_raw",
        // Present in every `main` prologue; their results only feed coroutine
        // state that no supported program reads.
        "kk_coroutine_current_context", "kk_native_heap_get", "kk_coroutine_current_is_active",
    ]

    /// Stdlib singleton/enum initialisers run from the `main` prologue. With no
    /// stdlib code executed (anything else falls back), nothing reads them.
    private static let stdlibInitPrefixes = [
        "kk_fn___companion_init_", "kk_fn___object_init_",
        "kk_fn___enum_static_init_", "kk_fn___kk_library_top_level_init_",
    ]

    private enum Callee {
        case user(KIRFunction)
        case builtin(String)
        case console(newline: Bool, hasArgument: Bool)
        case stdlibInit
    }

    private let kir: KIRModule
    private let sema: SemaModule
    private let interner: StringInterner
    private let globalSymbols: Set<SymbolID>
    private var globals: [SymbolID: IValue] = [:]
    private var labelIndexByFunction: [SymbolID: [Int32: Int]] = [:]
    private var output = ""
    private var depth = 0

    init(kir: KIRModule, sema: SemaModule, interner: StringInterner) {
        self.kir = kir
        self.sema = sema
        self.interner = interner
        var globals: Set<SymbolID> = []
        for decl in kir.arena.declarations {
            if case let .global(global) = decl { globals.insert(global.symbol) }
        }
        globalSymbols = globals
    }

    // MARK: - Entry

    func execute(entry: SymbolID) -> KIRInterpreterOutcome {
        guard let function = kir.arena.function(for: entry) else {
            return .fallback(reason: "entry function has no body")
        }
        guard function.params.isEmpty else {
            return .fallback(reason: "entry point takes arguments")
        }
        if let reason = analyze(entry: function) {
            return .fallback(reason: reason)
        }
        do {
            _ = try call(function, arguments: [])
            return .completed(stdout: output)
        } catch let bail as InterpreterBail {
            return .fallback(reason: bail.reason)
        } catch {
            return .fallback(reason: "\(error)")
        }
    }

    // MARK: - Static analysis

    private func resolveCallee(symbol: SymbolID?, name: InternedString) -> Callee? {
        if let symbol, let function = kir.arena.function(for: symbol) {
            return .user(function)
        }
        if let symbol, let console = consoleCallee(symbol) {
            return console
        }
        let resolved = interner.resolve(name)
        if Self.supportedBuiltins.contains(resolved) {
            return .builtin(resolved)
        }
        if Self.stdlibInitPrefixes.contains(where: { resolved.hasPrefix($0) }) {
            return .stdlibInit
        }
        return nil
    }

    /// `kotlin.io.print/println` with no argument or one non-null `String`.
    private func consoleCallee(_ symbol: SymbolID) -> Callee? {
        guard let info = sema.symbols.symbol(symbol), info.fqName.count == 3,
              interner.resolve(info.fqName[0]) == "kotlin", interner.resolve(info.fqName[1]) == "io"
        else { return nil }
        let newline: Bool
        switch interner.resolve(info.fqName[2]) {
        case "println": newline = true
        case "print": newline = false
        default: return nil
        }
        guard let signature = sema.symbols.functionSignature(for: symbol),
              signature.receiverType == nil, signature.contextReceiverTypes.isEmpty
        else { return nil }
        if signature.parameterTypes.isEmpty { return .console(newline: newline, hasArgument: false) }
        if signature.parameterTypes == [sema.types.stringType] {
            return .console(newline: newline, hasArgument: true)
        }
        return nil
    }

    /// Returns the first reason the program cannot be interpreted, or nil.
    private func analyze(entry: KIRFunction) -> String? {
        var visited: Set<SymbolID> = [entry.symbol]
        var worklist = [entry]
        while let function = worklist.popLast() {
            let name = interner.resolve(function.name)
            if function.isSuspend { return "suspend function \(name)" }
            let paramSymbols = Set(function.params.map(\.symbol))
            for instruction in function.body {
                switch instruction {
                case .nop, .beginBlock, .endBlock, .label, .jump, .jumpIfEqual, .jumpIfNotNull,
                     .copy, .returnUnit, .returnValue:
                    break
                case let .constValue(_, value):
                    switch value {
                    case .intLiteral, .longLiteral, .boolLiteral, .stringLiteral, .charLiteral, .unit, .null:
                        break
                    case let .symbolRef(symbol) where paramSymbols.contains(symbol) || globalSymbols.contains(symbol):
                        break
                    default:
                        return "constant \(value) in \(name)"
                    }
                case let .loadGlobal(_, symbol), let .storeGlobal(_, symbol):
                    guard globalSymbols.contains(symbol) else { return "external global in \(name)" }
                case let .call(symbol, callee, _, _, _, _, isSuperCall, _):
                    guard !isSuperCall else { return "super call in \(name)" }
                    guard let resolved = resolveCallee(symbol: symbol, name: callee) else {
                        return "call to \(interner.resolve(callee)) in \(name)"
                    }
                    if case let .user(target) = resolved, visited.insert(target.symbol).inserted {
                        worklist.append(target)
                    }
                default:
                    return "instruction \(instruction) in \(name)"
                }
            }
        }
        return nil
    }

    // MARK: - Execution

    private func labelIndex(for function: KIRFunction) -> [Int32: Int] {
        if let cached = labelIndexByFunction[function.symbol] { return cached }
        var index: [Int32: Int] = [:]
        for (position, instruction) in function.body.enumerated() {
            if case let .label(id) = instruction { index[id] = position }
        }
        labelIndexByFunction[function.symbol] = index
        return index
    }

    private func call(_ function: KIRFunction, arguments: [IValue]) throws -> IValue {
        guard depth < Self.maxCallDepth else { throw InterpreterBail(reason: "call depth exceeded") }
        guard arguments.count == function.params.count else {
            throw InterpreterBail(reason: "arity mismatch calling \(interner.resolve(function.name))")
        }
        depth += 1
        defer { depth -= 1 }

        var params: [SymbolID: IValue] = [:]
        for (parameter, argument) in zip(function.params, arguments) { params[parameter.symbol] = argument }
        var registers: [Int32: IValue] = [:]
        let labels = labelIndex(for: function)
        let body = function.body
        var pc = 0

        // A register naming a top-level property aliases that property's
        // storage: native codegen stores writes to it into the global.
        func globalAlias(_ id: KIRExprID) -> SymbolID? {
            if case let .symbolRef(symbol)? = kir.arena.expr(id), globalSymbols.contains(symbol) { return symbol }
            return nil
        }
        func write(_ id: KIRExprID, _ value: IValue) {
            registers[id.rawValue] = value
            if let symbol = globalAlias(id) { globals[symbol] = value }
        }
        func read(_ id: KIRExprID) throws -> IValue {
            if let symbol = globalAlias(id) { return globals[symbol] ?? .int(0) }
            if let value = registers[id.rawValue] { return value }
            if let expr = kir.arena.expr(id) {
                switch expr {
                case let .intLiteral(v), let .longLiteral(v): return .int(v)
                case let .boolLiteral(b): return .int(b ? 1 : 0)
                case let .stringLiteral(s): return .string(interner.resolve(s))
                case .null: return .null
                default: break
                }
            }
            throw InterpreterBail(reason: "uninitialized register r\(id.rawValue)")
        }
        func jump(to label: Int32) throws {
            guard let target = labels[label] else { throw InterpreterBail(reason: "unknown label L\(label)") }
            pc = target
        }

        while pc < body.count {
            let instruction = body[pc]
            pc += 1
            switch instruction {
            case .nop, .beginBlock, .endBlock, .label:
                break
            case let .jump(label):
                try jump(to: label)
            case let .jumpIfEqual(lhs, rhs, target):
                if try read(lhs) == read(rhs) { try jump(to: target) }
            case let .jumpIfNotNull(value, target):
                if try read(value) != .null { try jump(to: target) }
            case let .constValue(result, value):
                if case let .symbolRef(symbol) = value, params[symbol] == nil, globalSymbols.contains(symbol) {
                    break // alias binding only; the global keeps its value
                }
                registers[result.rawValue] = try constant(value, params: params)
            case let .copy(from, to):
                write(to, try read(from))
            case let .loadGlobal(result, symbol):
                registers[result.rawValue] = globals[symbol] ?? .int(0)
            case let .storeGlobal(value, symbol):
                globals[symbol] = try read(value)
            case .returnUnit:
                return .unit
            case let .returnValue(id):
                return try read(id)
            case let .call(symbol, calleeName, arguments, result, _, thrownResult, _, _):
                guard let callee = resolveCallee(symbol: symbol, name: calleeName) else {
                    throw InterpreterBail(reason: "call to \(interner.resolve(calleeName))")
                }
                let values = try arguments.map(read)
                let value: IValue
                switch callee {
                case let .user(target): value = try call(target, arguments: values)
                case let .builtin(name): value = try callBuiltin(name, values)
                case let .console(newline, hasArgument): value = try console(newline, hasArgument, values)
                case .stdlibInit: value = .unit
                }
                if let result { write(result, value) }
                // No supported callee throws (those paths bail out), so the
                // thrown channel always reports "no exception".
                if let thrownResult { registers[thrownResult.rawValue] = .int(0) }
            default:
                throw InterpreterBail(reason: "instruction \(instruction)")
            }
        }
        return .unit
    }

    private func constant(_ value: KIRExprKind, params: [SymbolID: IValue]) throws -> IValue {
        switch value {
        case let .intLiteral(v), let .longLiteral(v): return .int(v)
        case let .charLiteral(c): return .int(Int64(c))
        case let .boolLiteral(b): return .int(b ? 1 : 0)
        case let .stringLiteral(s): return .string(interner.resolve(s))
        case .unit: return .unit
        case .null: return .null
        case let .symbolRef(symbol):
            if let parameter = params[symbol] { return parameter }
            throw InterpreterBail(reason: "unresolved symbol reference")
        default: throw InterpreterBail(reason: "constant \(value)")
        }
    }

    private func console(_ newline: Bool, _ hasArgument: Bool, _ args: [IValue]) throws -> IValue {
        var text = ""
        if hasArgument {
            guard args.count == 1, case let .string(s) = args[0] else {
                throw InterpreterBail(reason: "console argument is not a string")
            }
            text = s
        }
        output += newline ? text + "\n" : text
        return .unit
    }

    private func callBuiltin(_ name: String, _ args: [IValue]) throws -> IValue {
        func int(_ index: Int) throws -> Int64 {
            guard index < args.count, case let .int(v) = args[index] else {
                throw InterpreterBail(reason: "\(name): expected integer operand")
            }
            return v
        }
        func narrow32(_ v: Int64) -> Int64 { Int64(Int32(truncatingIfNeeded: v)) }
        func flag(_ condition: Bool) -> IValue { .int(condition ? 1 : 0) }

        switch name {
        case "kk_unbox_int_static", "kk_unbox_bool_static", "kk_unbox_long_static",
             "kk_box_int", "kk_box_bool", "kk_box_long", "kk_box_long_nonnull",
             "kk_box_int_static", "kk_box_bool_static", "kk_box_long_static",
             "kk_box_long_nonnull_static", "kk_box_byte_static", "kk_box_short_static",
             "kk_unbox_int", "kk_unbox_bool", "kk_unbox_long":
            guard args.count == 1 else { throw InterpreterBail(reason: "\(name): arity") }
            return args[0]
        case "kk_int_narrow": return .int(narrow32(try int(0)))
        case "kk_uint_narrow": return .int(try int(0) & 0xFFFF_FFFF)
        case "kk_op_add": return .int(try int(0) &+ int(1))
        case "kk_op_sub": return .int(try int(0) &- int(1))
        case "kk_op_mul": return .int(try int(0) &* int(1))
        case "kk_op_div", "kk_op_mod", "kk_op_rem":
            let lhs = try int(0), rhs = try int(1)
            // ArithmeticException must be catchable natively; not modelled here.
            guard rhs != 0 else { throw InterpreterBail(reason: "division by zero") }
            if lhs == .min && rhs == -1 { return .int(name == "kk_op_div" ? .min : 0) }
            return .int(name == "kk_op_div" ? lhs / rhs : lhs % rhs)
        case "kk_op_eq":
            guard args.count == 2 else { throw InterpreterBail(reason: "\(name): arity") }
            return flag(args[0] == args[1])
        case "kk_op_ne":
            guard args.count == 2 else { throw InterpreterBail(reason: "\(name): arity") }
            return flag(args[0] != args[1])
        case "kk_double_equals":
            let a = Double(bitPattern: UInt64(bitPattern: try int(0)))
            let b = Double(bitPattern: UInt64(bitPattern: try int(1)))
            return flag((a.isNaN && b.isNaN) || a.bitPattern == b.bitPattern)
        case "kk_float_equals":
            let a = Float(bitPattern: UInt32(truncatingIfNeeded: try int(0)))
            let b = Float(bitPattern: UInt32(truncatingIfNeeded: try int(1)))
            return flag((a.isNaN && b.isNaN) || a.bitPattern == b.bitPattern)
        case "kk_nullable_double_equals":
            guard args.count == 2 else { throw InterpreterBail(reason: "\(name): arity") }
            let lhsNull = args[0] == .null, rhsNull = args[1] == .null
            if lhsNull || rhsNull { return flag(lhsNull && rhsNull) }
            let a = Double(bitPattern: UInt64(bitPattern: try int(0)))
            let b = Double(bitPattern: UInt64(bitPattern: try int(1)))
            return flag((a.isNaN && b.isNaN) || a.bitPattern == b.bitPattern)
        case "kk_nullable_float_equals":
            guard args.count == 2 else { throw InterpreterBail(reason: "\(name): arity") }
            let lhsNull = args[0] == .null, rhsNull = args[1] == .null
            if lhsNull || rhsNull { return flag(lhsNull && rhsNull) }
            let a = Float(bitPattern: UInt32(truncatingIfNeeded: try int(0)))
            let b = Float(bitPattern: UInt32(truncatingIfNeeded: try int(1)))
            return flag((a.isNaN && b.isNaN) || a.bitPattern == b.bitPattern)
        case "kk_nullable_primitive_eq", "kk_nullable_primitive_ne":
            guard args.count == 3, case let .int(peerFlag) = args[2] else {
                throw InterpreterBail(reason: "\(name): arity")
            }
            // Mirrors runtimeNullablePrimitiveEqualityCheck: flag 0/1 use
            // value equality once nullness is ruled out; flags 2-5 mark a
            // Double/Float peer and compare IEEE-754 (boxes are identity in
            // the interpreter, so a raw word is already the payload bits).
            let equal: Bool
            if peerFlag >= 2 {
                let nullableIsNull = args[0] == .null
                let peerIsNull = (peerFlag == 4 || peerFlag == 5) && args[1] == .null
                if nullableIsNull || peerIsNull {
                    equal = nullableIsNull && peerIsNull
                } else if peerFlag == 2 || peerFlag == 4 {
                    let a = Double(bitPattern: UInt64(bitPattern: try int(0)))
                    let b = Double(bitPattern: UInt64(bitPattern: try int(1)))
                    equal = a == b
                } else {
                    let a = Float(bitPattern: UInt32(truncatingIfNeeded: try int(0)))
                    let b = Float(bitPattern: UInt32(truncatingIfNeeded: try int(1)))
                    equal = a == b
                }
            } else {
                let nullableIsNull = args[0] == .null
                let peerIsNull = peerFlag != 0 && args[1] == .null
                equal = nullableIsNull || peerIsNull
                    ? nullableIsNull && peerIsNull
                    : args[0] == args[1]
            }
            return flag(name == "kk_nullable_primitive_eq" ? equal : !equal)
        case "kk_op_lt": return flag(try int(0) < int(1))
        case "kk_op_le", "__kk_int_range_induction_le": return flag(try int(0) <= int(1))
        case "kk_op_gt": return flag(try int(0) > int(1))
        case "kk_op_ge": return flag(try int(0) >= int(1))
        case "__kk_int_range_induction_add": return .int(try int(0) &+ int(1))
        case "kk_op_and": return flag(try int(0) != 0 && int(1) != 0)
        case "kk_op_or": return flag(try int(0) != 0 || int(1) != 0)
        case "kk_op_not": return flag(try int(0) == 0)
        case "kk_bitwise_and": return .int(try int(0) & int(1))
        case "kk_bitwise_or": return .int(try int(0) | int(1))
        case "kk_bitwise_xor": return .int(try int(0) ^ int(1))
        case "kk_op_ishl":
            let lhs = try int(0), amount = try int(1) & 31
            return .int(narrow32(lhs << amount))
        case "kk_op_ishr":
            let lhs = try int(0), amount = try int(1) & 31
            return .int(narrow32(lhs) >> amount)
        case "__kk_string_concat_flat":
            guard args.count == 2, case let .string(l) = args[0], case let .string(r) = args[1] else {
                throw InterpreterBail(reason: "string concat of non-string operands")
            }
            return .string(l + r)
        case "kk_any_to_string":
            guard args.count == 2, case let .int(tag) = args[1] else {
                throw InterpreterBail(reason: "kk_any_to_string: arity")
            }
            if args[0] == .null { return .string("null") }
            if args[0] == .unit { return .string("kotlin.Unit") }
            if case let .string(s) = args[0], tag == 3 { return .string(s) }
            guard case let .int(v) = args[0] else { throw InterpreterBail(reason: "kk_any_to_string: operand") }
            // Floating-point/ULong tags are decoded before the null check
            // natively and need their own formatting; only Int/Boolean/Long
            // here (Long shares the Int rendering inside the `.int` domain).
            guard tag == 1 || tag == 2 || tag == 8 else { throw InterpreterBail(reason: "kk_any_to_string tag \(tag)") }
            return .string(tag == 2 ? (v != 0 ? "true" : "false") : String(v))
        case "__kk_print_raw", "__kk_println_raw":
            guard args.count == 1, case let .string(s) = args[0] else {
                throw InterpreterBail(reason: "\(name): argument is not a string")
            }
            output += name == "__kk_println_raw" ? s + "\n" : s
            return .unit
        case "kk_coroutine_current_context", "kk_native_heap_get", "kk_coroutine_current_is_active":
            return .int(0)
        default:
            throw InterpreterBail(reason: "unsupported builtin \(name)")
        }
    }
}
