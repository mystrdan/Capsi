// Capsi - resource-file preprocessor shim.
//
// Why this exists
// ---------------
// `tauri-build` embeds the icon, application manifest and version metadata into
// the executable. That step happens in `tauri-build`'s build script and goes
// through `embed-resource`, which on a `*-pc-windows-gnu` target shells out to
// GNU `windres`. `windres` does not read a `.rc` file directly: it first pipes
// it through a C preprocessor, defaulting to `gcc -E`, and fails outright with
// "preprocessing failed" when no `gcc` can be run.
//
// A Windows GNU Rust toolchain cannot satisfy that. Rust ships a *linker-only*
// `gcc` for the target (see `GCC-WARNING.txt` next to it) and no C compiler at
// all, so `gcc -E` cannot work even though `gcc` is present. The result is that
// resource embedding always fails on a machine without MinGW/MSYS2 installed -
// a failure that looks like a bug in Capsi's own build rather than a missing
// tool.
//
// What it does
// ------------
// The resource file `tauri-winres` writes is already fully expanded: a
// `VERSIONINFO` block, `ICON` statements and a manifest reference, with no
// `#include` and no macros. Its only preprocessor directive is
// `#pragma code_page(65001)`. So the whole contract `windres` depends on is
// "copy the input to stdout", which is exactly what this program implements.
//
// `#pragma code_page(65001)` is dropped on the way through, because `windres`
// has no `code_page` pragma of its own and would reject it. This loses nothing:
// `embed-resource` always passes `-c 65001` to `windres` for the GNU target,
// which sets the same default code page the pragma asks for.
//
// What it deliberately refuses to do
// ----------------------------------
// It is not a C compiler and will not pretend to be one. Any invocation that is
// not preprocessing (`-E`) exits with an explanatory error, so a crate that
// actually needs to compile C still fails loudly instead of mysteriously.
//
// Build and install with `scripts\install-rc-preproc.bat`.

use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Read, Write};
use std::process::ExitCode;

/// Name reported in diagnostics, so a confusing error can be traced back here.
const NAME: &str = "capsi-rc-preproc";

fn main() -> ExitCode {
    let args: Vec<OsString> = env::args_os().skip(1).collect();
    let as_text: Vec<String> = args
        .iter()
        .map(|arg| arg.to_string_lossy().into_owned())
        .collect();

    if as_text.iter().any(|arg| arg == "--version") {
        println!("{NAME} (Capsi resource-file preprocessor) 1.0.0");
        return ExitCode::SUCCESS;
    }

    if !as_text.iter().any(|arg| arg == "-E") {
        eprintln!(
            "{NAME}: refusing to run as a C compiler (asked to run `gcc {}`).\n\
             Only `gcc -E <file>` - the preprocessing step GNU `windres` uses to read a \
             `.rc` file - is supported.\n\
             If this build genuinely needs to compile C, install mingw-w64 (or the Visual \
             Studio C++ build tools) so a real compiler is on PATH.",
            as_text.join(" ")
        );
        return ExitCode::FAILURE;
    }

    match preprocess(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{NAME}: cannot preprocess: {error}");
            ExitCode::FAILURE
        }
    }
}

/// Copy the input file - or stdin, when `windres` pipes the file in - to stdout,
/// minus the `code_page` pragma described above.
fn preprocess(args: &[OsString]) -> io::Result<()> {
    // `windres` invokes `<preprocessor> -E [-I<dir>] [-D<sym>] <input>`, so the
    // input is the last argument that is not an option.
    let mut input: Option<&OsString> = None;
    for arg in args {
        if !arg.to_string_lossy().starts_with('-') {
            input = Some(arg);
        }
    }

    let source = match input {
        // `-` means stdin.
        Some(path) if path.as_os_str() != "-" => fs::read(path)?,
        _ => {
            let mut buffer = Vec::new();
            io::stdin().read_to_end(&mut buffer)?;
            buffer
        }
    };

    let mut stdout = io::stdout().lock();
    stdout.write_all(&strip_code_page_pragmas(&source))?;
    stdout.flush()
}

/// Drop every `#pragma code_page(...)` line, leaving all other bytes - line
/// endings, encoding and spacing included - untouched.
fn strip_code_page_pragmas(source: &[u8]) -> Vec<u8> {
    let mut stripped = Vec::with_capacity(source.len());

    for line in source.split_inclusive(|byte| *byte == b'\n') {
        let directive = trim_ascii(line);
        let drops = directive.starts_with(b"#pragma")
            && directive.windows(b"code_page".len()).any(|w| w == b"code_page");

        if !drops {
            stripped.extend_from_slice(line);
        }
    }

    stripped
}

/// Trim ASCII whitespace, which is enough for a directive whose body is ASCII.
fn trim_ascii(bytes: &[u8]) -> &[u8] {
    let start = bytes
        .iter()
        .position(|byte| !byte.is_ascii_whitespace())
        .unwrap_or(bytes.len());
    let end = bytes
        .iter()
        .rposition(|byte| !byte.is_ascii_whitespace())
        .map_or(start, |index| index + 1);
    &bytes[start..end]
}
