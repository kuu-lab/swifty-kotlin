package golden.sema

fun charSequenceLength(cs: CharSequence): Int = cs.length

fun charSequenceGet(cs: CharSequence): Char = cs.get(0)

fun charSequenceSubSequence(cs: CharSequence): CharSequence = cs.subSequence(0, 1)

fun stringAsCharSequence(): CharSequence = "hello"

fun stringBuilderAsCharSequence(): CharSequence = StringBuilder("hello")
