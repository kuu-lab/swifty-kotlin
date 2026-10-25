import Foundation

/// Expands a `*.kt.tmpl` bundled-stdlib template into several virtual `.kt`
/// sources. Primitive-array APIs repeat one skeleton per element type; the
/// template holds the skeleton once and `collectBundledStdlibSources` injects
/// each expansion exactly like a hand-written file of the same path.
///
/// Every directive is a whole line starting with `//@`:
///
///     //@ file <Name> <Type>...   output `<template dir>/<Name>.kt`; the body is stamped once per Type, in order
///     //@ header                  following lines are copied verbatim once to the top of every output
///     //@ body                    following lines are the per-type skeleton; `{{T}}` becomes the current Type
///     //@ only <Type>...          body lines up to `//@ end` are kept only for the listed Types
///     //@ except <Type>...        ... or for every Type but the listed ones
///     //@ else                    flips the open `only` / `except`
///     //@ end                     closes it (conditionals do not nest)
///     //@ note <text>             template-only comment, never copied to an output
///
/// Layout: header, then each Type's body with its trailing blank lines dropped
/// and one blank line between bodies, then a single final newline. Expansion is
/// a pure function of the template bytes, so identical input gives identical
/// output (the stdlib manifest hash and declaration order depend on that).
internal enum BundledStdlibTemplate {
    static let fileSuffix = ".kt.tmpl"
    private static let placeholder = "{{T}}"

    private struct Condition {
        let types: Set<String>
        var keepsListed: Bool
        var hasElse = false
    }

    /// - Parameters:
    ///   - template: raw template bytes.
    ///   - path: template path relative to the `Stdlib` directory; outputs are
    ///     placed next to it.
    /// - Returns: output paths in `//@ file` order, without the `.kt` suffix
    ///   (the `relativePaths` convention of `BundledStdlib`), with contents.
    static func expand(
        _ template: Data,
        at path: String
    ) throws -> [(relativePath: String, contents: Data)] {
        func failure(_ line: Int, _ reason: String) -> BundledStdlib.LoadError {
            .templateExpansionFailed(path: path, reason: "line \(line): \(reason)")
        }
        guard let text = String(data: template, encoding: .utf8) else {
            throw BundledStdlib.LoadError.templateExpansionFailed(path: path, reason: "not valid UTF-8")
        }
        var sourceLines = text.components(separatedBy: "\n")
        if sourceLines.last == "" { sourceLines.removeLast() }

        enum Section { case prologue, header, body }
        var section = Section.prologue
        var outputs: [(name: String, types: [String])] = []
        var knownTypes: Set<String> = []
        var header: [String] = []
        var body: [(text: String, condition: Condition?)] = []
        var open: Condition?

        for (index, line) in sourceLines.enumerated() {
            let number = index + 1
            guard line.hasPrefix("//@") else {
                switch section {
                case .header:
                    header.append(line)
                case .body:
                    if line.replacingOccurrences(of: placeholder, with: "").contains("{{") {
                        throw failure(number, "unknown placeholder (only \(placeholder) is supported)")
                    }
                    body.append((line, open))
                case .prologue:
                    // Only blank lines and ordinary comments may precede the header.
                    guard line.isEmpty || line.hasPrefix("//") else {
                        throw failure(number, "expected a //@ directive before //@ header")
                    }
                }
                continue
            }
            let words = line.dropFirst(3).split(separator: " ").map(String.init)
            guard let directive = words.first else { throw failure(number, "empty directive") }
            let arguments = Array(words.dropFirst())
            switch (directive, section) {
            case ("file", .prologue):
                guard let name = arguments.first, !name.contains("/"), arguments.count > 1 else {
                    throw failure(number, "usage: //@ file <Name> <Type>...")
                }
                guard !outputs.contains(where: { $0.name == name }) else {
                    throw failure(number, "duplicate output \(name)")
                }
                outputs.append((name, Array(arguments.dropFirst())))
                knownTypes.formUnion(arguments.dropFirst())
            case ("header", .prologue), ("body", .prologue), ("body", .header):
                guard !outputs.isEmpty else { throw failure(number, "//@ \(directive) before any //@ file") }
                section = directive == "header" ? .header : .body
            case ("only", .body), ("except", .body):
                guard open == nil else { throw failure(number, "conditionals do not nest") }
                guard !arguments.isEmpty, knownTypes.isSuperset(of: arguments) else {
                    throw failure(number, "//@ \(directive) needs Types declared by //@ file")
                }
                open = Condition(types: Set(arguments), keepsListed: directive == "only")
            case ("else", .body):
                guard var condition = open, !condition.hasElse else { throw failure(number, "unexpected //@ else") }
                condition.keepsListed.toggle()
                condition.hasElse = true
                open = condition
            case ("end", .body):
                guard open != nil else { throw failure(number, "unexpected //@ end") }
                open = nil
            case ("note", _):
                break
            default:
                throw failure(number, "unexpected directive //@ \(directive)")
            }
        }
        guard section == .body else {
            throw BundledStdlib.LoadError.templateExpansionFailed(path: path, reason: "missing //@ file, //@ header or //@ body")
        }
        guard open == nil else {
            throw BundledStdlib.LoadError.templateExpansionFailed(path: path, reason: "unterminated //@ only / //@ except")
        }

        let directory = (path as NSString).deletingLastPathComponent
        let headerText = header.map { $0 + "\n" }.joined()
        return outputs.map { output -> (relativePath: String, contents: Data) in
            let bodies = output.types.map { type -> String in
                var lines = body.compactMap { line -> String? in
                    if let condition = line.condition, condition.types.contains(type) != condition.keepsListed {
                        return nil
                    }
                    return line.text.replacingOccurrences(of: placeholder, with: type)
                }
                while lines.last == "" { lines.removeLast() }
                return lines.joined(separator: "\n")
            }
            let contents = headerText + bodies.joined(separator: "\n\n") + "\n"
            return (
                relativePath: (directory as NSString).appendingPathComponent(output.name),
                contents: Data(contents.utf8)
            )
        }
    }
}
