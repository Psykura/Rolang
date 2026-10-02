def main() -> i32 {
    let word = "héllo";
    if word.len() != 6 || word.scalar_count() != 5 || word.grapheme_count() != 5 { return 1; }
    let s = word.scalars();
    if s[1] != 233 || String.from_scalar(233) != "é" || String.from_scalar(0x1F600) != "\u{1F600}" { return 2; }
    // e + combining acute accent is one grapheme of two scalars.
    let combined = "e\u{301}";
    if combined.scalar_count() != 2 || combined.grapheme_count() != 1 || combined.graphemes()[0] != combined { return 3; }
    // Flags pair regional indicators; ZWJ sequences and skin tones stay together.
    let flags = "\u{1F1E8}\u{1F1F3}\u{1F1EF}\u{1F1F5}";
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}";
    let wave = "\u{1F44B}\u{1F3FD}";
    if flags.grapheme_count() != 2 || family.grapheme_count() != 1 || wave.grapheme_count() != 1 { return 4; }
    let mixed = f"a{family}b\r\n{wave}";
    let parts = mixed.graphemes();
    if parts.len() != 5 || parts[1] != family || parts[3] != "\r\n" { return 5; }
    if !"日本語".is_valid_utf8() || "日本語".scalar_count() != 3 { return 6; }
    let truncated = "日本語".slice(0..<4);
    if truncated.is_valid_utf8() || truncated.scalar_count() != 2 || truncated.scalars()[1] != 0xFFFD { return 7; }
    if '\u{1F600}' != 0x1F600 || "\u{41}\u{42}" != "AB" || "\u{zz}".len() != 5 { return 8; }
    0
}
