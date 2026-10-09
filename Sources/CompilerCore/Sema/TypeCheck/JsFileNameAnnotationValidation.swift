import Foundation

extension TypeCheckDriver {
    /// Checks the source-only `@file:JsFileName` argument after const values
    /// have been evaluated. Its JavaScript output naming effect is handled by
    /// the Kotlin/JS per-file backend, which this compiler does not provide.
    func validateJsFileNameAnnotationArguments(in files: [ASTFile]) {
        for file in files {
            for annotation in file.annotations {
                guard let annotationSymbol = resolveAnnotationSymbol(
                    named: annotation.name,
                    in: file,
                    symbols: sema.symbols,
                    interner: interner
                ),
                sema.symbols.symbol(annotationSymbol)?.fqName.map(interner.resolve)
                    == ["kotlin", "js", "JsFileName"]
                else {
                    continue
                }

                guard annotation.arguments.count == 1 else {
                    diagnostics.error(
                        "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-ARITY",
                        "Annotation 'JsFileName' requires exactly one String argument.",
                        range: file.range
                    )
                    continue
                }

                let rawArgument = annotationArgumentValue(annotation.arguments[0], parameterName: "name")
                if extractKotlinStringLiteralContent(rawArgument) != nil {
                    continue
                }

                if let valueType = constArgumentType(rawArgument, in: file) {
                    if valueType == "String" {
                        continue
                    }
                    diagnostics.error(
                        "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-TYPE",
                        "Argument type mismatch for 'JsFileName.name': expected String, got \(valueType).",
                        range: file.range
                    )
                    continue
                }

                if isNonStringLiteral(rawArgument) {
                    diagnostics.error(
                        "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-TYPE",
                        "Argument type mismatch for 'JsFileName.name': expected String.",
                        range: file.range
                    )
                } else {
                    diagnostics.error(
                        "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST",
                        "Annotation argument for 'JsFileName.name' must be a compile-time constant.",
                        range: file.range
                    )
                }
            }
        }
    }

    private func constArgumentType(_ raw: String, in file: ASTFile) -> String? {
        let components = raw.split(separator: ".").map(String.init)
        guard !components.isEmpty,
              components.joined(separator: ".") == raw,
              components.allSatisfy(isSimpleIdentifier)
        else {
            return nil
        }

        var candidates: [[InternedString]] = []
        if components.count == 1 {
            let shortName = interner.intern(components[0])
            for importDecl in file.imports where !importDecl.isWildcard {
                if importDecl.alias == shortName || (importDecl.alias == nil && importDecl.path.last == shortName) {
                    candidates.append(importDecl.path)
                }
            }
            candidates.append(file.packageFQName + [shortName])
        } else {
            let path = components.map(interner.intern)
            candidates.append(path)
            candidates.append(file.packageFQName + path)
            let firstName = path[0]
            for importDecl in file.imports where importDecl.alias == firstName {
                candidates.append(importDecl.path + path.dropFirst())
            }
        }

        for fqName in candidates {
            for symbolID in sema.symbols.lookupAll(fqName: fqName) {
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .property,
                      symbol.flags.contains(.constValue)
                else {
                    continue
                }
                if symbol.visibility == .private,
                   sema.symbols.sourceFileID(for: symbolID) != file.fileID
                {
                    continue
                }

                switch sema.symbols.constValueExprKind(for: symbolID) {
                case .stringLiteral?: return "String"
                case .intLiteral?: return "Int"
                case .longLiteral?: return "Long"
                case .boolLiteral?: return "Boolean"
                case .charLiteral?: return "Char"
                case .floatLiteral?: return "Float"
                case .doubleLiteral?: return "Double"
                default: continue
                }
            }
        }
        return nil
    }

    private func annotationArgumentValue(_ raw: String, parameterName: String) -> String {
        let pieces = raw.split(separator: "=", maxSplits: 1).map(String.init)
        guard pieces.count == 2,
              pieces[0].trimmingCharacters(in: .whitespacesAndNewlines) == parameterName
        else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isNonStringLiteral(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let numericValue = value.replacingOccurrences(of: "_", with: "")
        if Int64(numericValue) != nil || Double(numericValue) != nil
            || value == "true" || value == "false" || value == "null"
            || (value.count >= 3 && value.first == Character("'") && value.last == Character("'"))
        {
            return true
        }
        return false
    }

    private func isSimpleIdentifier(_ value: String) -> Bool {
        guard let first = value.first, first.isLetter || first == "_" else {
            return false
        }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
