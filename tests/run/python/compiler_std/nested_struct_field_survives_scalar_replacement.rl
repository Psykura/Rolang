
struct Span { var start: i32; var end: i32; }
struct Token { var span: Span; var text: String; }
def main() -> i32 {
    let token = Token { span: Span { start: 3, end: 7 }, text: "name" };
    let span = token.span;
    span.end = 9;
    if token.span.end != 9 { return 1; }
    return token.span.end - token.span.start - 6;
}
