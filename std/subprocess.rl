// Standard library: running programs, with pipes to their standard streams.
//
//     switch await Command.new("git").arg("status").arg("--short").output() {
//         case .ok(let result): println(f"{result.status}: {result.stdout}");
//         case .err(let error): eprintln(error.to_string());
//     }
//
//     guard let child = Command.new("sort").stdin(Stdio.piped).stdout(Stdio.piped).spawn().ok_value() else { return 1; }
//     await child.write("b\na\n");
//     let sorted = await child.output();   // closes stdin, reads stdout and stderr, waits
//
// Programs are found through PATH and run without a shell, so arguments need
// no quoting. Waiting runs on a helper thread, and piped streams are
// asynchronous, so other tasks keep running. A child that is never waited for
// is still reaped when it exits.
import "task.rl"
import "string.rl"
import "result.rl"
import "vec.rl"
import "range.rl"
import "async_io.rl"

pub extern "C" def rt_child_spawn(program: String, arguments: RawPtr, environment: RawPtr, cleared: i32,
    directory: String, input_mode: i32, output_mode: i32, error_mode: i32,
    input: RawPtr, output: RawPtr, errors: RawPtr, error: RawPtr) -> RawPtr;
pub extern "C" def rt_child_pid(child: RawPtr) -> i32;
pub extern "C" def rt_child_release(child: RawPtr) -> Void;
pub extern "C" def rt_child_wait_start(child: RawPtr) -> RawPtr;
pub extern "C" def rt_child_status(child: RawPtr, signal: RawPtr) -> i32;
pub extern "C" def rt_child_kill(child: RawPtr, signal: i32) -> i32;

// Where a child's standard stream goes.
pub enum Stdio {
    // The parent's own stream.
    case inherit;
    // A pipe the parent reads or writes through the Child.
    case piped;
    // /dev/null.
    case discard;
    def mode() -> i32 {
        switch self { case .inherit: return 0; case .piped: return 1; case .discard: return 2; }
    }
}

pub struct ProcessError {
    pub let message: String;
    pub def to_string() -> String { self.message }
}

// How a child ended: an exit code, or the signal that terminated it.
pub struct ExitStatus {
    pub let code: i32?;
    pub let signal: i32?;
    pub def success() -> Bool { self.code == 0 }
    pub def to_string() -> String {
        if let value = self.code { return f"exit code {value}"; }
        if let number = self.signal { return f"signal {number}"; }
        "unknown status"
    }
}

// A finished child's status and captured output.
pub struct Output {
    pub let status: ExitStatus;
    pub let stdout: String;
    pub let stderr: String;
}

// A program to run. Methods that configure it return the command, so calls chain.
pub struct Command {
    pub let program: String;
    let arguments: Vec<String>;
    let environment: Vec<String>;
    var cleared: Bool;
    var directory: String;
    var input: Stdio;
    var output_mode: Stdio;
    var error_mode: Stdio;

    pub static def new(program: String) -> Command {
        Command { program, arguments: Vec<String>.new(), environment: Vec<String>.new(), cleared: false, directory: "",
            input: Stdio.inherit, output_mode: Stdio.inherit, error_mode: Stdio.inherit }
    }
    pub def arg(value: String) -> Command { self.arguments.push(value); self }
    pub def args(values: Vec<String>) -> Command { for value in values { self.arguments.push(value); } self }
    // Sets an environment variable for the child.
    pub def env(name: String, value: String) -> Command { self.environment.push(name + "=" + value); self }
    // Starts the child with only the variables set through env().
    pub def env_clear() -> Command { self.cleared = true; self }
    pub def current_dir(path: String) -> Command { self.directory = path; self }
    pub def stdin(mode: Stdio) -> Command { self.input = mode; self }
    pub def stdout(mode: Stdio) -> Command { self.output_mode = mode; self }
    pub def stderr(mode: Stdio) -> Command { self.error_mode = mode; self }

    // Starts the program.
    pub def spawn() -> Result<Child, ProcessError> {
        let argv = Vec<String>.new();
        argv.push(self.program);
        for value in self.arguments { argv.push(value); }
        var cleared = 0; if self.cleared { cleared = 1; }
        var input: RawPtr; var output: RawPtr; var errors: RawPtr;
        var code: i32 = 0;
        var handle: RawPtr;
        unsafe {
            handle = rt_child_spawn(self.program, argv.raw_handle(), self.environment.raw_handle(), cleared, self.directory,
                self.input.mode(), self.output_mode.mode(), self.error_mode.mode(),
                input as RawPtr, output as RawPtr, errors as RawPtr, code as RawPtr);
        }
        if code != 0 {
            return Result<Child, ProcessError>.err(error: ProcessError { message: f"cannot run {self.program}: {os_error_message(code)}" });
        }
        unsafe {
            var stdin: AsyncStream? = nil; var stdout: AsyncStream? = nil; var stderr: AsyncStream? = nil;
            if (input as i64) != 0 { stdin = AsyncStream.from_raw_handle(input); }
            if (output as i64) != 0 { stdout = AsyncStream.from_raw_handle(output); }
            if (errors as i64) != 0 { stderr = AsyncStream.from_raw_handle(errors); }
            return Result<Child, ProcessError>.ok(value: Child { handle, pid: rt_child_pid(handle), stdin, stdout, stderr });
        }
    }
    // Runs the program to completion with stdout and stderr captured; stdin
    // reads nothing unless set.
    pub def output() async -> Result<Output, ProcessError> {
        switch self.input { case .inherit: self.input = Stdio.discard; default: {} }
        self.output_mode = Stdio.piped; self.error_mode = Stdio.piped;
        switch self.spawn() {
            case .ok(let child): return await child.output();
            case .err(let error): return Result<Output, ProcessError>.err(error: error);
        }
    }
    // Runs the program to completion with the parent's standard streams.
    pub def status() async -> Result<ExitStatus, ProcessError> {
        switch self.spawn() {
            case .ok(let child): return Result<ExitStatus, ProcessError>.ok(value: await child.wait());
            case .err(let error): return Result<ExitStatus, ProcessError>.err(error: error);
        }
    }
}

// A started program. Piped streams are available as stdin, stdout and stderr.
pub struct Child {
    var handle: RawPtr;
    pub let pid: i32;
    pub var stdin: AsyncStream?;
    pub var stdout: AsyncStream?;
    pub var stderr: AsyncStream?;

    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_child_release(handle);
        }
    }
    // Waits for the program to exit; may be called again.
    pub def wait() async -> ExitStatus {
        var signal: i32 = 0;
        var code: i32 = 0;
        unsafe {
            let waiting = Task<i32>.from_handle(rt_child_wait_start(self.handle));
            await waiting;
            code = rt_child_status(self.handle, signal as RawPtr);
        }
        if signal != 0 { return ExitStatus { code: nil, signal }; }
        // -1 without a signal: waiting failed and the status is unknown.
        if code < 0 { return ExitStatus { code: nil, signal: nil }; }
        ExitStatus { code, signal: nil }
    }
    // Sends a signal (SIGTERM by default); false when the program has exited.
    pub def kill(signal: i32 = 15) -> Bool {
        unsafe { return rt_child_kill(self.handle, signal) == 0; }
    }
    // Writes to the program's piped stdin.
    pub def write(data: String) async -> Result<i32, ProcessError> {
        guard let stream = self.stdin else { return Result<i32, ProcessError>.err(error: ProcessError { message: "stdin is not piped" }); }
        switch await stream.write(data) {
            case .ok(let count): return Result<i32, ProcessError>.ok(value: count);
            case .err(let code): return Result<i32, ProcessError>.err(error: ProcessError { message: f"write to {self.pid} failed: {os_error_message(code)}" });
        }
    }
    // Ends the program's input, so it reads end of file.
    pub def close_stdin() -> Void {
        if let stream = self.stdin { stream.shutdown_write(); }
        self.stdin = nil;
    }
    // Closes stdin, reads stdout and stderr to their ends (concurrently, so
    // neither pipe fills up) and waits for the program.
    pub def output() async -> Result<Output, ProcessError> {
        self.close_stdin();
        let out = spawn read_stream(self.stdout);
        let err = spawn read_stream(self.stderr);
        let stdout = await out;
        let stderr = await err;
        let status = await self.wait();
        guard let text = stdout else { return Result<Output, ProcessError>.err(error: ProcessError { message: "reading stdout failed" }); }
        guard let errors = stderr else { return Result<Output, ProcessError>.err(error: ProcessError { message: "reading stderr failed" }); }
        Result<Output, ProcessError>.ok(value: Output { status, stdout: text, stderr: errors })
    }
}

def read_stream(stream: AsyncStream?) async -> String? {
    guard let source = stream else { return ""; }
    switch await source.read_to_end() {
        case .ok(let data): return data;
        case .err(let code): return nil;
    }
}

// Runs `program` with `arguments` and captures its output.
pub def run(program: String, arguments: Vec<String> = Vec<String>.new()) async -> Result<Output, ProcessError> {
    await Command.new(program).args(arguments).output()
}

// Runs `script` with /bin/sh -c and captures its output. The script is
// interpreted by the shell: never build it from untrusted text.
pub def shell(script: String) async -> Result<Output, ProcessError> {
    await Command.new("/bin/sh").arg("-c").arg(script).output()
}
