fun iterableLastFamily(values: Iterable<String?>, probe: String?): String? {
    values.last()
    values.last { it == probe }
    values.lastIndexOf(probe)
    values.lastOrNull()
    return values.lastOrNull { it == probe }
}
