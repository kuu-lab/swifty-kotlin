import Foundation

/// Minimal mutable XML tree for Maven POMs and Android manifests. Attribute
/// names keep their source prefix (`android:name`), which is what both the
/// manifest merger and aapt2 expect; namespace declarations stay ordinary
/// attributes so serialization round-trips them.
///
/// Parsing is self-contained rather than FoundationXML: on Linux that
/// module links against the host libxml2, whose symbols CI runners lack.
package final class AndroidXMLElement {
    package var name: String
    package var attributes: [(String, String)]
    package var children: [AndroidXMLElement] = []
    package var text: String = ""

    package init(name: String, attributes: [(String, String)] = []) {
        self.name = name
        self.attributes = attributes
    }

    package subscript(attribute key: String) -> String? {
        get { attributes.first(where: { $0.0 == key })?.1 }
        set {
            if let index = attributes.firstIndex(where: { $0.0 == key }) {
                if let newValue { attributes[index].1 = newValue } else { attributes.remove(at: index) }
            } else if let newValue {
                attributes.append((key, newValue))
            }
        }
    }

    /// First child with `name`, ignoring any namespace prefix on the child.
    package func child(_ name: String) -> AndroidXMLElement? {
        children.first { $0.localName == name }
    }

    package func children(_ name: String) -> [AndroidXMLElement] {
        children.filter { $0.localName == name }
    }

    package var localName: String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    /// Trimmed text of the child named `name`.
    package func value(_ name: String) -> String? {
        child(name).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    package func copy() -> AndroidXMLElement {
        let element = AndroidXMLElement(name: name, attributes: attributes)
        element.text = text
        element.children = children.map { $0.copy() }
        return element
    }

    package static func parse(_ data: Data) throws -> AndroidXMLElement {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AndroidPackagingError.invalidInput("Malformed XML: not UTF-8")
        }
        var reader = Reader(Array(text.unicodeScalars))
        return try reader.document()
    }

    package func serialized() -> String {
        var output = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        write(into: &output, indent: "")
        return output
    }

    private func write(into output: inout String, indent: String) {
        output += indent + "<" + name
        for (key, value) in attributes {
            output += " \(key)=\"\(Self.escape(value))\""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if children.isEmpty && trimmed.isEmpty {
            output += " />\n"
            return
        }
        output += ">"
        if !trimmed.isEmpty { output += Self.escape(trimmed) }
        if !children.isEmpty {
            output += "\n"
            for child in children { child.write(into: &output, indent: indent + "    ") }
            output += indent
        }
        output += "</\(name)>\n"
    }

    private static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    /// Elements, attributes, text, comments, CDATA, the XML declaration and
    /// DOCTYPE, and the predefined and numeric entities: what POMs and
    /// Android manifests contain.
    private struct Reader {
        let scalars: [Unicode.Scalar]
        var index = 0

        init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

        mutating func document() throws -> AndroidXMLElement {
            if scalars.first == "\u{FEFF}" { index = 1 }
            var root: AndroidXMLElement?
            while true {
                skipWhitespace()
                guard index < scalars.count else { break }
                if try skipMarkup() { continue }
                guard root == nil, peek("<") else { throw fail("unexpected content outside the root element") }
                root = try parseElement()
            }
            guard let root else { throw fail("no root element") }
            return root
        }

        private mutating func parseElement() throws -> AndroidXMLElement {
            try expect("<")
            let element = AndroidXMLElement(name: try name(), attributes: [])
            var attributes: [(String, String)] = []
            while true {
                skipWhitespace()
                if consume("/>") { break }
                if consume(">") {
                    try content(of: element)
                    break
                }
                let key = try name()
                skipWhitespace()
                try expect("=")
                skipWhitespace()
                guard index < scalars.count, scalars[index] == "\"" || scalars[index] == "'" else {
                    throw fail("attribute \(key) has no quoted value")
                }
                let quote = scalars[index]
                index += 1
                var value = ""
                while index < scalars.count, scalars[index] != quote {
                    if scalars[index] == "&" { value += try entity() } else { value.unicodeScalars.append(scalars[index]); index += 1 }
                }
                try expect(String(quote))
                attributes.append((key, value))
            }
            // Same order as before: xmlns first, then package/android:name, then the rest.
            element.attributes = attributes.sorted { Self.attributeOrder($0.0, $1.0) }
            return element
        }

        private mutating func content(of element: AndroidXMLElement) throws {
            while index < scalars.count {
                if consume("</") {
                    let closing = try name()
                    guard closing == element.name else { throw fail("</\(closing)> closes <\(element.name)>") }
                    skipWhitespace()
                    try expect(">")
                    return
                }
                if consume("<![CDATA[") {
                    while index < scalars.count, !peek("]]>") { element.text.unicodeScalars.append(scalars[index]); index += 1 }
                    try expect("]]>")
                } else if try skipMarkup() {
                    continue
                } else if peek("<") {
                    element.children.append(try parseElement())
                } else if scalars[index] == "&" {
                    element.text += try entity()
                } else {
                    element.text.unicodeScalars.append(scalars[index])
                    index += 1
                }
            }
            throw fail("<\(element.name)> is not closed")
        }

        /// Comments, processing instructions and DOCTYPE carry nothing we use.
        private mutating func skipMarkup() throws -> Bool {
            for (open, close) in [("<!--", "-->"), ("<?", "?>"), ("<!DOCTYPE", ">")] where consume(open) {
                while index < scalars.count, !peek(close) { index += 1 }
                try expect(close)
                return true
            }
            return false
        }

        private mutating func entity() throws -> String {
            try expect("&")
            var body = ""
            while index < scalars.count, scalars[index] != ";", body.count < 12 {
                body.unicodeScalars.append(scalars[index])
                index += 1
            }
            try expect(";")
            switch body {
            case "amp": return "&"
            case "lt": return "<"
            case "gt": return ">"
            case "quot": return "\""
            case "apos": return "'"
            default:
                let value = body.hasPrefix("#x") ? UInt32(body.dropFirst(2), radix: 16)
                    : body.hasPrefix("#") ? UInt32(body.dropFirst()) : nil
                guard let value, let scalar = Unicode.Scalar(value) else { throw fail("unknown entity &\(body);") }
                return String(Character(scalar))
            }
        }

        private mutating func name() throws -> String {
            var result = ""
            while index < scalars.count {
                let scalar = scalars[index]
                guard scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                        || ":_-.".unicodeScalars.contains(scalar) else { break }
                result.unicodeScalars.append(scalar)
                index += 1
            }
            guard !result.isEmpty else { throw fail("expected a name") }
            return result
        }

        private mutating func skipWhitespace() {
            while index < scalars.count, scalars[index].properties.isWhitespace { index += 1 }
        }

        private func peek(_ text: String) -> Bool {
            let pattern = Array(text.unicodeScalars)
            return index + pattern.count <= scalars.count && Array(scalars[index..<index + pattern.count]) == pattern
        }

        private mutating func consume(_ text: String) -> Bool {
            guard peek(text) else { return false }
            index += text.unicodeScalars.count
            return true
        }

        private mutating func expect(_ text: String) throws {
            guard consume(text) else { throw fail("expected '\(text)'") }
        }

        private func fail(_ reason: String) -> AndroidPackagingError {
            let line = scalars[..<min(index, scalars.count)].filter { $0 == "\n" }.count + 1
            return .invalidInput("Malformed XML at line \(line): \(reason)")
        }

        /// `xmlns` declarations first, then `package`/`android:name`, then
        /// the rest alphabetically, so merged manifests read like the input.
        private static func attributeOrder(_ lhs: String, _ rhs: String) -> Bool {
            func rank(_ key: String) -> Int {
                if key.hasPrefix("xmlns") { return 0 }
                if key == "package" || key == "android:name" { return 1 }
                return 2
            }
            let (left, right) = (rank(lhs), rank(rhs))
            return left != right ? left < right : lhs < rhs
        }
    }
}
