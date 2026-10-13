package java.nio.charset

public class IllegalCharsetNameException(public val charsetName: String) : IllegalArgumentException(charsetName)
public class UnsupportedCharsetException(public val charsetName: String) : IllegalArgumentException(charsetName)
