// Amortized linear byte-oriented text construction. Copies on to_string().
import "string.rl"

pub extern "C" def rt_string_builder_new() -> RawPtr;
pub extern "C" def rt_string_builder_append(builder: RawPtr, text: String) -> Void;
pub extern "C" def rt_string_builder_byte(builder: RawPtr, byte: u8) -> Void;
pub extern "C" def rt_string_builder_len(builder: RawPtr) -> i64;
pub extern "C" def rt_string_builder_clear(builder: RawPtr) -> Void;
pub extern "C" def rt_string_builder_text(builder: RawPtr) -> RawPtr;
pub extern "C" def rt_string_builder_free(builder: RawPtr) -> Void;

pub struct StringBuilder {
    var handle: RawPtr;

    pub static def new() -> StringBuilder {
        unsafe { return StringBuilder { handle: rt_string_builder_new() }; }
    }
    pub def __release__() -> Void {
        unsafe { rt_string_builder_free(self.handle); }
    }
    pub def append(text: String) -> Void {
        unsafe { rt_string_builder_append(self.handle, text); }
    }
    // Appends a raw byte; callers are responsible for UTF-8 validity.
    pub def append_byte(byte: u8) -> Void {
        unsafe { rt_string_builder_byte(self.handle, byte); }
    }
    pub def append_line(text: String) -> Void {
        self.append(text);
        self.append_byte(10 as u8);
    }
    pub def len() -> i64 {
        unsafe { return rt_string_builder_len(self.handle); }
    }
    // Keeps allocated capacity for reuse.
    pub def clear() -> Void {
        unsafe { rt_string_builder_clear(self.handle); }
    }
    pub def to_string() -> String {
        unsafe { return String.from_handle(rt_string_builder_text(self.handle)); }
    }
}
