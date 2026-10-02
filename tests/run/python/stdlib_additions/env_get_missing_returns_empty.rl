
import "process.rl"
import "string.rl"

def main() -> i32 {
    let v = env_get("THIS_DEFINITELY_DOES_NOT_EXIST_12345");
    return v.len() as i32;
}
