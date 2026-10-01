// LLVM's opaque-pointer textual IR. Values carry their LLVM storage type;
// builders reject mismatched stores/calls before returning a module artifact.
import std.string_builder

extern "C" def memcpy(dst: RawPtr, src: RawPtr, size: i64) -> RawPtr;

pub struct LlvmValue {
    pub let type: String;
    pub let text: String;
    pub def typed() -> String { self.type + " " + self.text }
}
pub def llvm_quote(text: String) -> String {
    let result = StringBuilder.new(); result.append("\"");
    let hex = "0123456789ABCDEF";
    for i in 0..<(text.len() as i32) {
        let byte = text.byte_at(i);
        if byte == 34 || byte == 92 || byte < 32 || byte >= 127 {
            result.append_byte(92 as u8);
            result.append_byte(hex.byte_at(byte / 16) as u8);
            result.append_byte(hex.byte_at(byte % 16) as u8);
        } else { result.append_byte(byte as u8); }
    }
    result.append("\""); result.to_string()
}
pub def llvm_global(name: String) -> String { "@" + llvm_quote(name) }
pub def llvm_float(value: f64, single: Bool) -> String {
    // LLVM hex literals encode the exact double bits, including NaN and -0.
    // A float literal uses the double encoding of its rounded f32 value.
    var number = value;
    if single { number = (value as f32) as f64; }
    var bits: u64 = 0;
    unsafe { memcpy(bits as RawPtr, number as RawPtr, 8); }
    let hex = "0123456789ABCDEF"; let result = StringBuilder.new(); result.append("0x");
    var shift = 60;
    while shift >= 0 {
        result.append_byte(hex.byte_at(((bits >> (shift as u64)) & (15 as u64)) as i32) as u8);
        shift -= 4;
    }
    result.to_string()
}
pub def llvm_width(type: String) -> i32 {
    if type.equals("i1") { return 1; } if type.equals("i8") { return 8; }
    if type.equals("i16") { return 16; } if type.equals("i32") { return 32; }
    if type.equals("i64") { return 64; } 0
}
pub struct LlvmSignature {
    pub let name: String;
    pub let result: String;
    pub let params: Vec<String>;
    pub let defined: Bool;
    pub def declaration() -> String {
        let text = StringBuilder.new(); text.append("declare " + self.result + " " + llvm_global(self.name) + "(");
        for i in 0..<self.params.len() { if i > 0 { text.append(", "); } text.append(self.params[i]); }
        text.append(")"); text.to_string()
    }
}
pub struct LlvmIrBuilder {
    pub let output: StringBuilder;
    pub let errors: Vec<String>;
    var next_id: i32;
    pub static def new(errors: Vec<String>) -> LlvmIrBuilder {
        LlvmIrBuilder { output: StringBuilder.new(), errors, next_id: 0 }
    }
    pub def line(text: String) -> Void { self.output.append_line(text); }
    pub def fresh() -> String { let id = self.next_id; self.next_id += 1; f"v{id}" }
    pub def value(type: String, expression: String) -> LlvmValue {
        let name = "%" + self.fresh(); self.line("  " + name + " = " + expression);
        LlvmValue { type, text: name }
    }
    pub def load(type: String, pointer: String) -> LlvmValue {
        self.value(type, "load " + type + ", ptr " + pointer + ", align 1")
    }
    pub def store(value: LlvmValue, type: String, pointer: String) -> Void {
        if !value.type.equals(type) { self.errors.push("LLVM store type mismatch: " + value.type + " -> " + type); return; }
        self.line("  store " + value.typed() + ", ptr " + pointer + ", align 1");
    }
    pub def gep(pointer: String, offset: String) -> String {
        self.value("ptr", "getelementptr i8, ptr " + pointer + ", i64 " + offset).text
    }
    pub def cast(op: String, value: LlvmValue, type: String) -> LlvmValue {
        if value.type.equals(type) { return value; }
        self.value(type, op + " " + value.typed() + " to " + type)
    }
    pub def coerce(value: LlvmValue, type: String, signed: Bool = true) -> LlvmValue {
        if value.type.equals(type) { return value; }
        let source = llvm_width(value.type); let target = llvm_width(type);
        if source > 0 && target > 0 {
            if source > target { return self.cast("trunc", value, type); }
            var op = "sext"; if source == 1 || !signed { op = "zext"; }
            return self.cast(op, value, type);
        }
        self.errors.push("LLVM coercion type mismatch: " + value.type + " -> " + type);
        LlvmValue { type, text: "zeroinitializer" }
    }
    pub def binary(op: String, a: LlvmValue, b: LlvmValue) -> LlvmValue {
        if !a.type.equals(b.type) { self.errors.push("LLVM binary type mismatch: " + a.type + " / " + b.type); }
        self.value(a.type, op + " " + a.typed() + ", " + b.text)
    }
    pub def compare(op: String, a: LlvmValue, b: LlvmValue) -> LlvmValue {
        if !a.type.equals(b.type) { self.errors.push("LLVM comparison type mismatch: " + a.type + " / " + b.type); }
        self.value("i1", op + " " + a.typed() + ", " + b.text)
    }
    pub def call(callee: String, result: String, args: Vec<LlvmValue>) -> LlvmValue {
        let text = StringBuilder.new(); text.append("call " + result + " " + callee + "(");
        for i in 0..<args.len() { if i > 0 { text.append(", "); } text.append(args[i].typed()); }
        text.append(")");
        if result.equals("void") { self.line("  " + text.to_string()); return LlvmValue { type: result, text: "" }; }
        self.value(result, text.to_string())
    }
}
