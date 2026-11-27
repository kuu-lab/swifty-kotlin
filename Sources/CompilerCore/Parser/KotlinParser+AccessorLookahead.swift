extension KotlinParser {
    func isPropertyAccessorStart(allowsBodyless: Bool = true) -> Bool {
        LeanParser.isPropertyAccessorStart(self, allowsBodyless: allowsBodyless)
    }

    func propertyTailContainsAccessorHeader(_ children: [SyntaxChild]) -> Bool {
        LeanParser.propertyTailContainsAccessorHeader(self, children: children)
    }
}
