package golden.sema

fun useReplaceChar(): String = "hello world".replace('l', 'r')

fun useReplaceStringIgnoreCase(): String = "Hello World".replace("hello", "Hi", ignoreCase = true)

fun useReplaceCharIgnoreCase(): String = "Hello World".replace('h', 'J', ignoreCase = true)

fun useReplaceCharCaseSensitive(): String = "Hello World".replace('H', 'J', ignoreCase = false)
