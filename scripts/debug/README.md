# Debug & Crash Analysis Utilities

This directory contains standalone Python and PowerShell utilities used to capture, parse, and analyze Windows minidumps and memory states for `aa_roas.exe`:

- **`make_dump.ps1`**: Captures a live process minidump (`dump.dmp`) using `dbghelp.dll`.
- **`parse_dump.py`**: Parses streams, thread list, context, registers, and module tables from a minidump.
- **`all_threads.py`**: Extracts stack bounds and RIP/EIP instructions across all active worker threads.
- **`read_stack.py`**: Dumps and unwinds guest stack pointers to identify calling functions and XDK symbols.
- **`resolve_rvas.py`**: Resolves Relative Virtual Addresses (RVAs) against symbols in `config/game.toml`.
- **`find_strings.py`**: Scans guest memory dumps for ASCII / Unicode engine strings and package names.
