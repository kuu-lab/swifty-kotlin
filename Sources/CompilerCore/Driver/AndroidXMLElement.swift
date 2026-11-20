import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Minimal mutable XML tree for Maven POMs and Android manifests. Attribute
/// names keep their source prefix (`android:name`), which is what both the
/// manifest merger and aapt2 expect; namespace declarations stay ordinary
/// attributes so serialization round-trips them.
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
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let root = builder.root else {
            let reason = parser.parserError.map { String(describing: $0) } ?? "no root element"
            throw AndroidPackagingError.invalidInput("Malformed XML: \(reason)")
        }
        return root
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

    private final class Builder: NSObject, XMLParserDelegate {
        var root: AndroidXMLElement?
        var stack: [AndroidXMLElement] = []

        func parser(
            _ parser: XMLParser, didStartElement elementName: String,
            namespaceURI: String?, qualifiedName: String?, attributes: [String: String]
        ) {
            // XMLParser reports attributes as an unordered dictionary; sort
            // for deterministic output (aapt2 does not depend on order).
            let element = AndroidXMLElement(
                name: qualifiedName ?? elementName,
                attributes: attributes.sorted { Self.attributeOrder($0.key, $1.key) }
            )
            if let parent = stack.last { parent.children.append(element) } else { root = element }
            stack.append(element)
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String,
            namespaceURI: String?, qualifiedName: String?
        ) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
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
