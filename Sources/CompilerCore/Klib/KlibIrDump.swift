import Foundation

/// Textual dump of a ``KlibIrModule`` for inspection and tests —
/// `klib dump-ir` style, much coarser: one line per file/declaration with
/// resolved names, symbol kinds, and flag summaries.
package enum KlibIrDump {

    package static func dump(_ module: KlibIrModule) throws -> String {
        var out = ""
        guard module.hasIR else {
            return "klib has no serialized IR\n"
        }
        for fileIndex in 0 ..< module.fileCount {
            let file = try module.file(fileIndex)
            let package = try module.fqName(file.fqName, fileIndex: fileIndex)
            out += "file[\(fileIndex)] package \(package.isEmpty ? "<root>" : package)"
            if let entryId = file.fileEntryId {
                let entry = try module.fileEntry(entryId, fileIndex: fileIndex)
                let name = entry.nameIndex.map { (try? module.string($0, fileIndex: fileIndex)) ?? "?" } ?? entry.nameOld ?? "?"
                out += " entry=\(name)"
            }
            out += " declarations=\(file.declarationIds.count)\n"
            for declId in file.declarationIds {
                let declaration = try module.declaration(declId, fileIndex: fileIndex)
                try dumpDeclaration(declaration, module: module, fileIndex: fileIndex, indent: "  ", into: &out)
            }
        }
        return out
    }

    private static func dumpDeclaration(
        _ declaration: KlibIrDeclaration,
        module: KlibIrModule,
        fileIndex: Int,
        indent: String,
        into out: inout String
    ) throws {
        switch declaration {
        case .anonymousInit(let init_):
            out += "\(indent)anonymous-init body=\(init_.bodyIndex)\n"
        case .class(let cls):
            let flags = cls.base.flags
            let supertypes = try cls.superTypes.map { try typeSummary(try module.type($0, fileIndex: fileIndex), module: module, fileIndex: fileIndex) }
            out += "\(indent)class \(name(cls.nameIndex, module: module, fileIndex: fileIndex))"
            out += " kind=\(flags.classKind) \(flags.visibility) \(flags.modality)"
            if !supertypes.isEmpty { out += " : \(supertypes.joined(separator: ", "))" }
            out += "\(try symbolSuffix(cls.base, module: module, fileIndex: fileIndex))\n"
            for member in cls.declarations {
                try dumpDeclaration(member, module: module, fileIndex: fileIndex, indent: indent + "  ", into: &out)
            }
        case .constructor(let ctor):
            let base = ctor.base
            out += "\(indent)constructor(\(try parameterSummary(base)))\(try symbolSuffix(base.base, module: module, fileIndex: fileIndex)) body=\(base.bodyIndex.map(String.init) ?? "-")\n"
        case .enumEntry(let entry):
            out += "\(indent)enum-entry \(name(entry.nameIndex, module: module, fileIndex: fileIndex))\(try symbolSuffix(entry.base, module: module, fileIndex: fileIndex))\n"
        case .field(let field):
            out += "\(indent)field \(try module.nameAndTypeDescription(field.nameType, fileIndex: fileIndex))\(try symbolSuffix(field.base, module: module, fileIndex: fileIndex))\n"
        case .function(let function):
            try dumpFunction(function.base, label: "fun", module: module, fileIndex: fileIndex, indent: indent, into: &out)
            for override in function.overridden {
                out += "\(indent)  overrides \(try module.symbolDescription(override, fileIndex: fileIndex))\n"
            }
        case .property(let property):
            out += "\(indent)property \(name(property.nameIndex, module: module, fileIndex: fileIndex))"
            out += property.backingField != nil ? " +field" : ""
            out += property.getter != nil ? " +getter" : ""
            out += property.setter != nil ? " +setter" : ""
            out += "\(try symbolSuffix(property.base, module: module, fileIndex: fileIndex))\n"
            if let field = property.backingField {
                out += "\(indent)  .field \(try module.nameAndTypeDescription(field.nameType, fileIndex: fileIndex))\(try symbolSuffix(field.base, module: module, fileIndex: fileIndex))\n"
            }
            if let getter = property.getter {
                try dumpFunction(getter.base, label: ".get", module: module, fileIndex: fileIndex, indent: indent + "  ", into: &out)
            }
            if let setter = property.setter {
                try dumpFunction(setter.base, label: ".set", module: module, fileIndex: fileIndex, indent: indent + "  ", into: &out)
            }
        case .typeParameter(let parameter):
            out += "\(indent)type-parameter \(name(parameter.nameIndex, module: module, fileIndex: fileIndex))\n"
        case .variable(let variable):
            out += "\(indent)var \(try module.nameAndTypeDescription(variable.nameType, fileIndex: fileIndex))\n"
        case .valueParameter(let parameter):
            out += "\(indent)value-parameter \(try module.nameAndTypeDescription(parameter.nameType, fileIndex: fileIndex))\n"
        case .localDelegatedProperty(let delegated):
            out += "\(indent)local-delegated-property \(try module.nameAndTypeDescription(delegated.nameType, fileIndex: fileIndex))\n"
        case .typeAlias(let alias):
            out += "\(indent)typealias \(try module.nameAndTypeDescription(alias.nameType, fileIndex: fileIndex))\(try symbolSuffix(alias.base, module: module, fileIndex: fileIndex))\n"
        }
    }

    private static func dumpFunction(
        _ function: KlibFunctionBase,
        label: String,
        module: KlibIrModule,
        fileIndex: Int,
        indent: String,
        into out: inout String
    ) throws {
        let flags = function.base.flags
        out += "\(indent)\(label) \(try module.nameAndTypeDescription(function.nameType, fileIndex: fileIndex))"
        out += " \(flags.visibility) \(flags.modality)"
        if flags.isInline { out += " inline" }
        if flags.isSuspend { out += " suspend" }
        if flags.isOperator { out += " operator" }
        if flags.isInfix { out += " infix" }
        if flags.isExternalFunction { out += " external" }
        out += " params=(\(try parameterSummary(function)))"
        if !function.typeParameters.isEmpty {
            out += " typeParams=\(function.typeParameters.count)"
        }
        out += " body=\(function.bodyIndex.map(String.init) ?? "-")"
        out += "\(try symbolSuffix(function.base, module: module, fileIndex: fileIndex))\n"
    }

    private static func parameterSummary(_ function: KlibFunctionBase) throws -> String {
        "\(function.regularParameters.count) value, \(function.contextParameters.count) ctx, ext=\(function.extensionReceiver != nil), dispatch=\(function.dispatchReceiver != nil)"
    }

    private static func name(_ index: Int32, module: KlibIrModule, fileIndex: Int) -> String {
        (try? module.string(index, fileIndex: fileIndex)) ?? "<bad-string:\(index)>"
    }

    private static func symbolSuffix(_ base: KlibDeclBase, module: KlibIrModule, fileIndex: Int) throws -> String {
        let description = (try? module.symbolDescription(base.symbol, fileIndex: fileIndex)) ?? "?"
        return " | \(base.symbol.kind) sig[\(base.symbol.signatureIndex)]=\(description)"
    }

    private static func typeSummary(_ type: KlibIrType, module: KlibIrModule, fileIndex: Int) throws -> String {
        switch type {
        case .simple(let classifier, let nullability, let arguments, _):
            var text = try module.symbolDescription(classifier, fileIndex: fileIndex)
            if !arguments.isEmpty {
                text += "<\(arguments.count) args>"
            }
            if nullability == .markedNullable { text += "?" }
            return text
        case .legacySimple(let classifier, let nullable, let arguments, _):
            var text = try module.symbolDescription(classifier, fileIndex: fileIndex)
            if !arguments.isEmpty { text += "<\(arguments.count) args>" }
            if nullable { text += "?" }
            return text
        case .dynamic:
            return "dynamic"
        case .error:
            return "<error-type>"
        case .definitelyNotNull(let types):
            return "dnn[\(types.map(String.init).joined(separator: ","))]"
        }
    }
}
