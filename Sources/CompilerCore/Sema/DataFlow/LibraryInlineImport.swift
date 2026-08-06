import Foundation

extension DataFlowSemaPhase {
    func parseImportedInlineFunction(
        path: String,
        importedSymbol: SymbolID,
        signature: FunctionSignature?,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        externalLinkNameToSymbol: [String: SymbolID]
    ) -> KIRFunction? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0002",
                "Unable to read inline KIR artifact: \(path)",
                range: nil
            )
            return nil
        }

        var functionName = interner.intern("__imported_inline_\(importedSymbol.rawValue)")
        let signatureParameterCount = (signature?.receiverType != nil ? 1 : 0) + (signature?.parameterTypes.count ?? 0)
        var parsedParameterCount = max(0, signatureParameterCount)
        var parsedParameterSymbols: [Int32] = []
        var isSuspend = false
        var bodyLines: [String] = []
        var inBody = false

        // Bound the number of KIR parameters that can be requested by an
        // untrusted inline KIR artifact.  This prevents a tiny `params=<huge>`
        // line from driving a billion-iteration allocation loop.
        let maxAllowedParameterCount = 100_000

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            if inBody {
                bodyLines.append(line)
                continue
            }
            if line == "body:" {
                inBody = true
                continue
            }
            guard let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<separatorIndex])
            let value = String(line[line.index(after: separatorIndex)...])
            switch key {
            case "nameB64":
                if let decoded = decodeBase64String(value) {
                    functionName = interner.intern(decoded)
                }
            case "params":
                if let rawValue = Int(value) {
                    parsedParameterCount = max(0, rawValue)
                    guard parsedParameterCount <= maxAllowedParameterCount else {
                        diagnostics.error(
                            "KSWIFTK-LIB-0020",
                            "Inline KIR parameter count \(parsedParameterCount) in '\(path)' exceeds the maximum supported (\(maxAllowedParameterCount))",
                            range: nil
                        )
                        return nil
                    }
                }
            case "paramSymbols":
                parsedParameterSymbols = parseInlineIntList(value).map(Int32.init)
                guard parsedParameterSymbols.count <= maxAllowedParameterCount else {
                    diagnostics.error(
                        "KSWIFTK-LIB-0020",
                        "Inline KIR parameter-symbol count \(parsedParameterSymbols.count) in '\(path)' exceeds the maximum supported (\(maxAllowedParameterCount))",
                        range: nil
                    )
                    return nil
                }
            case "suspend":
                isSuspend = value == "1" || value == "true"
            default:
                continue
            }
        }

        parsedParameterCount = max(parsedParameterCount, parsedParameterSymbols.count)
        guard parsedParameterCount <= maxAllowedParameterCount else {
            diagnostics.error(
                "KSWIFTK-LIB-0020",
                "Inline KIR parameter count \(parsedParameterCount) in '\(path)' exceeds the maximum supported (\(maxAllowedParameterCount))",
                range: nil
            )
            return nil
        }
        var params: [KIRParameter] = []
        var parameterSymbolMapping: [Int32: SymbolID] = [:]
        let hasReceiver = signature?.receiverType != nil
        for index in 0 ..< parsedParameterCount {
            let localSymbol = importedInlineParameterSymbol(functionSymbol: importedSymbol, index: index)
            let paramType: TypeID
            if let signature, index == 0, let receiverType = signature.receiverType {
                paramType = receiverType
            } else if let signature, index < parsedParameterCount {
                let parameterIndex = index - (hasReceiver ? 1 : 0)
                if parameterIndex >= 0 && parameterIndex < signature.parameterTypes.count {
                    paramType = signature.parameterTypes[parameterIndex]
                } else {
                    paramType = types.anyType
                }
            } else {
                paramType = types.anyType
            }
            params.append(KIRParameter(symbol: localSymbol, type: paramType))
            if index < parsedParameterSymbols.count {
                parameterSymbolMapping[parsedParameterSymbols[index]] = localSymbol
            }
        }

        var body: [KIRInstruction] = []
        body.reserveCapacity(bodyLines.count)
        var importLabelCounter: Int32 = 900_000
        var importExprCounter: Int32 = 900_000
        for line in bodyLines {
            let instructions = parseImportedInlineInstructions(
                line: line,
                parameterSymbolMapping: parameterSymbolMapping,
                interner: interner,
                labelCounter: &importLabelCounter,
                exprCounter: &importExprCounter,
                externalLinkNameToSymbol: externalLinkNameToSymbol
            )
            body.append(contentsOf: instructions)
        }
        if body.isEmpty {
            body = [.returnUnit]
        }

        return KIRFunction(
            symbol: importedSymbol,
            name: functionName,
            params: params,
            returnType: signature?.returnType ?? types.anyType,
            body: body,
            isSuspend: isSuspend,
            isInline: true
        )
    }

    private func importedInlineParameterSymbol(functionSymbol: SymbolID, index: Int) -> SymbolID {
        let raw = Int32(truncatingIfNeeded: Int64(-200_000) - Int64(functionSymbol.rawValue) * 64 - Int64(index))
        return SymbolID(rawValue: raw)
    }

    private func parseImportedInlineInstructions(
        line: String,
        parameterSymbolMapping: [Int32: SymbolID],
        interner: StringInterner,
        labelCounter: inout Int32,
        exprCounter: inout Int32,
        externalLinkNameToSymbol: [String: SymbolID]
    ) -> [KIRInstruction] {
        let parts = line.split(separator: " ")
        guard let opcode = parts.first else {
            return []
        }
        let pairs = parseInlineKeyValuePairs(parts.dropFirst())

        // Legacy select: expand to control flow (jumpIfEqual + copy + jump + label)
        if opcode == "select" {
            guard let conditionRaw = pairs["condition"], let condition = Int32(conditionRaw),
                  let thenRaw = pairs["then"], let thenValue = Int32(thenRaw),
                  let elseRaw = pairs["else"], let elseValue = Int32(elseRaw),
                  let resultRaw = pairs["result"], let result = Int32(resultRaw)
            else {
                return []
            }
            let elseLabel = labelCounter
            let endLabel = labelCounter + 1
            labelCounter += 2
            let falseExprID = KIRExprID(rawValue: exprCounter)
            exprCounter += 1
            // Define result expr so InlineLoweringPass can clone it via localExprMap
            return [
                .constValue(result: KIRExprID(rawValue: result), value: .unit),
                .constValue(result: falseExprID, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: KIRExprID(rawValue: condition), rhs: falseExprID, target: elseLabel),
                .copy(from: KIRExprID(rawValue: thenValue), to: KIRExprID(rawValue: result)),
                .jump(endLabel),
                .label(elseLabel),
                .copy(from: KIRExprID(rawValue: elseValue), to: KIRExprID(rawValue: result)),
                .label(endLabel),
            ]
        }

        guard let instruction = parseImportedInlineInstruction(
            line: line,
            pairs: pairs,
            opcode: opcode,
            parameterSymbolMapping: parameterSymbolMapping,
            interner: interner,
            externalLinkNameToSymbol: externalLinkNameToSymbol
        ) else {
            return []
        }
        return [instruction]
    }

    private func parseImportedInlineInstruction(
        line _: String,
        pairs: [String: String],
        opcode: Substring,
        parameterSymbolMapping: [Int32: SymbolID],
        interner: StringInterner,
        externalLinkNameToSymbol: [String: SymbolID]
    ) -> KIRInstruction? {
        switch opcode {
        case "nop":
            return .nop
        case "beginBlock":
            return .beginBlock
        case "endBlock":
            return .endBlock
        case "label":
            guard let raw = pairs["id"], let id = Int32(raw) else { return nil }
            return .label(id)
        case "jump":
            guard let raw = pairs["target"], let target = Int32(raw) else { return nil }
            return .jump(target)
        case "jumpIfEqual":
            guard let lhsRaw = pairs["lhs"], let lhs = Int32(lhsRaw),
                  let rhsRaw = pairs["rhs"], let rhs = Int32(rhsRaw),
                  let targetRaw = pairs["target"], let target = Int32(targetRaw)
            else {
                return nil
            }
            return .jumpIfEqual(
                lhs: KIRExprID(rawValue: lhs),
                rhs: KIRExprID(rawValue: rhs),
                target: target
            )
        case "const":
            guard let resultRaw = pairs["result"], let result = Int32(resultRaw),
                  let valueToken = pairs["value"],
                  let value = parseImportedInlineExprKind(
                      token: valueToken,
                      parameterSymbolMapping: parameterSymbolMapping,
                      interner: interner
                  )
            else {
                return nil
            }
            return .constValue(result: KIRExprID(rawValue: result), value: value)
        case "binary":
            guard let opRaw = pairs["op"], let op = parseBinaryOp(opRaw),
                  let lhsRaw = pairs["lhs"], let lhs = Int32(lhsRaw),
                  let rhsRaw = pairs["rhs"], let rhs = Int32(rhsRaw),
                  let resultRaw = pairs["result"], let result = Int32(resultRaw)
            else {
                return nil
            }
            return .binary(
                op: op,
                lhs: KIRExprID(rawValue: lhs),
                rhs: KIRExprID(rawValue: rhs),
                result: KIRExprID(rawValue: result)
            )
        case "unary":
            guard let opRaw = pairs["op"], let op = parseUnaryOp(opRaw),
                  let operandRaw = pairs["operand"], let operand = Int32(operandRaw),
                  let resultRaw = pairs["result"], let result = Int32(resultRaw)
            else {
                return nil
            }
            return .unary(
                op: op,
                operand: KIRExprID(rawValue: operand),
                result: KIRExprID(rawValue: result)
            )
        case "copy":
            guard let fromRaw = pairs["from"], let from = Int32(fromRaw),
                  let toRaw = pairs["to"], let to = Int32(toRaw)
            else {
                return nil
            }
            return .copy(
                from: KIRExprID(rawValue: from),
                to: KIRExprID(rawValue: to)
            )
        case "nullAssert":
            guard let operandRaw = pairs["operand"], let operand = Int32(operandRaw),
                  let resultRaw = pairs["result"], let result = Int32(resultRaw)
            else {
                return nil
            }
            return .nullAssert(
                operand: KIRExprID(rawValue: operand),
                result: KIRExprID(rawValue: result)
            )
        case "jumpIfNotNull":
            guard let valueRaw = pairs["value"], let value = Int32(valueRaw),
                  let targetRaw = pairs["target"], let target = Int32(targetRaw)
            else {
                return nil
            }
            return .jumpIfNotNull(
                value: KIRExprID(rawValue: value),
                target: target
            )
        case "storeGlobal":
            guard let valueRaw = pairs["value"], let value = Int32(valueRaw),
                  let symbolRaw = pairs["symbol"], let symbol = Int32(symbolRaw)
            else {
                return nil
            }
            return .storeGlobal(
                value: KIRExprID(rawValue: value),
                symbol: SymbolID(rawValue: symbol)
            )
        case "loadGlobal":
            guard let resultRaw = pairs["result"], let result = Int32(resultRaw),
                  let symbolRaw = pairs["symbol"], let symbol = Int32(symbolRaw)
            else {
                return nil
            }
            return .loadGlobal(
                result: KIRExprID(rawValue: result),
                symbol: SymbolID(rawValue: symbol)
            )
        case "rethrow":
            guard let valueRaw = pairs["value"], let value = Int32(valueRaw) else {
                return nil
            }
            return .rethrow(value: KIRExprID(rawValue: value))
        case "beginFinallyGuard":
            return .beginFinallyGuard
        case "endFinallyGuard":
            return .endFinallyGuard
        case "returnUnit":
            return .returnUnit
        case "returnValue":
            guard let valueRaw = pairs["value"], let value = Int32(valueRaw) else {
                return nil
            }
            return .returnValue(KIRExprID(rawValue: value))
        case "returnIfEqual":
            guard let lhsRaw = pairs["lhs"], let lhs = Int32(lhsRaw),
                  let rhsRaw = pairs["rhs"], let rhs = Int32(rhsRaw)
            else {
                return nil
            }
            return .returnIfEqual(
                lhs: KIRExprID(rawValue: lhs),
                rhs: KIRExprID(rawValue: rhs)
            )
        case "nonLocalReturn":
            guard let valueRaw = pairs["value"], let value = Int32(valueRaw) else {
                return nil
            }
            return .nonLocalReturn(KIRExprID(rawValue: value))
        case "nonLocalReturnUnit":
            return .nonLocalReturn(nil)
        case "call":
            guard let calleeEncoded = pairs["calleeB64"],
                  let calleeName = decodeBase64String(calleeEncoded)
            else {
                return nil
            }
            let args = parseInlineIntList(pairs["args"] ?? "[]").map { value in
                KIRExprID(rawValue: Int32(truncatingIfNeeded: value))
            }
            let result: KIRExprID? = if let resultRaw = pairs["result"], resultRaw != "_" {
                Int32(resultRaw).map(KIRExprID.init(rawValue:))
            } else {
                nil
            }
            let canThrowRaw = pairs["canThrow"] ?? "0"
            let canThrow = canThrowRaw == "1" || canThrowRaw == "true"
            let isSuperCallRaw = pairs["isSuperCall"] ?? "0"
            let isSuperCall = isSuperCallRaw == "1" || isSuperCallRaw == "true"
            var callSymbol: SymbolID? = nil
            var resolvedCalleeName = calleeName
            if let linkEncoded = pairs["linkB64"],
               let linkName = decodeBase64String(linkEncoded),
               !linkName.isEmpty
            {
                if let consumerSymbol = externalLinkNameToSymbol[linkName] {
                    callSymbol = consumerSymbol
                } else {
                    // The callee is defined by the library itself (a mangled
                    // `kk_fn_*` symbol in its object archive) and has no
                    // counterpart in the consumer's symbol table. The declared
                    // name would not resolve at link time, so call the library
                    // symbol directly.
                    resolvedCalleeName = linkName
                }
            }
            return .call(
                symbol: callSymbol,
                callee: interner.intern(resolvedCalleeName),
                arguments: args,
                result: result,
                canThrow: canThrow,
                thrownResult: nil,
                isSuperCall: isSuperCall
            )
        default:
            return nil
        }
    }

    private func parseImportedInlineExprKind(
        token: String,
        parameterSymbolMapping: [Int32: SymbolID],
        interner: StringInterner
    ) -> KIRExprKind? {
        if token == "unit" {
            return .unit
        }
        if token == "null" {
            return .null
        }
        if token.hasPrefix("int:") {
            let value = String(token.dropFirst("int:".count))
            return Int64(value).map(KIRExprKind.intLiteral)
        }
        if token.hasPrefix("long:") {
            let value = String(token.dropFirst("long:".count))
            return Int64(value).map(KIRExprKind.longLiteral)
        }
        if token.hasPrefix("uint:") {
            let value = String(token.dropFirst("uint:".count))
            return UInt64(value).map(KIRExprKind.uintLiteral)
        }
        if token.hasPrefix("ulong:") {
            let value = String(token.dropFirst("ulong:".count))
            return UInt64(value).map(KIRExprKind.ulongLiteral)
        }
        if token.hasPrefix("float:") {
            let value = String(token.dropFirst("float:".count))
            return Double(value).map(KIRExprKind.floatLiteral)
        }
        if token.hasPrefix("double:") {
            let value = String(token.dropFirst("double:".count))
            return Double(value).map(KIRExprKind.doubleLiteral)
        }
        if token.hasPrefix("char:") {
            let value = String(token.dropFirst("char:".count))
            return UInt32(value).map(KIRExprKind.charLiteral)
        }
        if token.hasPrefix("bool:") {
            let value = String(token.dropFirst("bool:".count))
            return .boolLiteral(value == "1" || value == "true")
        }
        if token.hasPrefix("stringB64:") {
            let encoded = String(token.dropFirst("stringB64:".count))
            guard let decoded = decodeBase64String(encoded) else {
                return nil
            }
            return .stringLiteral(interner.intern(decoded))
        }
        if token.hasPrefix("symbol:") {
            let raw = String(token.dropFirst("symbol:".count))
            guard let symbolRaw = Int32(raw) else {
                return nil
            }
            if let mapped = parameterSymbolMapping[symbolRaw] {
                return .symbolRef(mapped)
            }
            return .symbolRef(SymbolID(rawValue: symbolRaw))
        }
        if token.hasPrefix("temp:") {
            let raw = String(token.dropFirst("temp:".count))
            return Int32(raw).map(KIRExprKind.temporary)
        }
        if token.hasPrefix("externB64:") {
            let encoded = String(token.dropFirst("externB64:".count))
            guard let decoded = decodeBase64String(encoded) else {
                return nil
            }
            return .externSymbolAddress(interner.intern(decoded))
        }
        if token.hasPrefix("extern:") {
            let name = String(token.dropFirst("extern:".count))
            return .externSymbolAddress(interner.intern(name))
        }
        return nil
    }

    private func parseBinaryOp(_ raw: String) -> KIRBinaryOp? {
        switch raw {
        case "add":
            .add
        case "subtract":
            .subtract
        case "multiply":
            .multiply
        case "divide":
            .divide
        case "modulo":
            .modulo
        case "equal":
            .equal
        case "notEqual":
            .notEqual
        case "lessThan":
            .lessThan
        case "lessOrEqual":
            .lessOrEqual
        case "greaterThan":
            .greaterThan
        case "greaterOrEqual":
            .greaterOrEqual
        case "logicalAnd":
            .logicalAnd
        case "logicalOr":
            .logicalOr
        default:
            nil
        }
    }

    private func parseUnaryOp(_ raw: String) -> KIRUnaryOp? {
        switch raw {
        case "not":
            .not
        case "unaryPlus":
            .unaryPlus
        case "unaryMinus":
            .unaryMinus
        default:
            nil
        }
    }

    private func parseInlineKeyValuePairs(_ tokens: ArraySlice<Substring>) -> [String: String] {
        var mapping: [String: String] = [:]
        for token in tokens {
            guard let separatorIndex = token.firstIndex(of: "=") else {
                continue
            }
            let key = String(token[..<separatorIndex])
            let value = String(token[token.index(after: separatorIndex)...])
            mapping[key] = value
        }
        return mapping
    }

    private func parseInlineIntList(_ token: String) -> [Int] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let inner: Substring
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            inner = trimmed.dropFirst().dropLast()
        } else {
            inner = Substring(trimmed)
        }
        if inner.isEmpty {
            return []
        }
        return inner.split(separator: ",").compactMap { Int($0) }
    }

    private func decodeBase64String(_ token: String) -> String? {
        guard let data = Data(base64Encoded: token),
              let decoded = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return decoded
    }
}
