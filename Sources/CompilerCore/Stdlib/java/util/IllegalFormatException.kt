package java.util

// Runtime formatting errors expose this hierarchy for typed catch clauses.
public open class IllegalFormatException : IllegalArgumentException()

public class DuplicateFormatFlagsException : IllegalFormatException()
public class FormatFlagsConversionMismatchException : IllegalFormatException()
public class IllegalFormatCodePointException : IllegalFormatException()
public class IllegalFormatConversionException : IllegalFormatException()
public class IllegalFormatFlagsException : IllegalFormatException()
public class IllegalFormatPrecisionException : IllegalFormatException()
public class IllegalFormatWidthException : IllegalFormatException()
public class MissingFormatArgumentException : IllegalFormatException()
public class MissingFormatWidthException : IllegalFormatException()
public class UnknownFormatConversionException : IllegalFormatException()
public class UnknownFormatFlagsException : IllegalFormatException()
