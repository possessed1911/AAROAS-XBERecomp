import struct

rvas = [
    0xcc6fa1,
    0xcc7692,
    0xcadf9d,
    0xcae094,
    0xcae789,
    0xccd52c,
    0xac200d,
    0xcb1731,
    0x2a9275,
    0x2de1e1,
    0x30ecf8,
    0x30f481,
    0x30e670,
    0x30c275,
    0xabad5a,
    0x530e,
    0x7f059,
    0xaa8ebd,
    0xac37e9,
    0xac24b6
]

# We can find which function contains each RVA by reading exports of aa_roas.dll!
with open("out/build/release/aa_roas.dll", "rb") as f:
    f.seek(0x3c)
    e_lfanew, = struct.unpack("<I", f.read(4))
    
    # OptionalHeader.DataDirectory[0] = Export Table
    f.seek(e_lfanew + 4 + 20 + 96 + 16) # for 64-bit PE: PE header(4) + FileHeader(20) + OptionalHeader standard/windows(96) + DataDirectory(0 is export)
    # wait, OptionalHeader64 has DataDirectory at offset 112 from start of OptionalHeader
    f.seek(e_lfanew + 4 + 20 + 112)
    exp_rva, exp_size = struct.unpack("<II", f.read(8))
    print(f"Export table RVA: {exp_rva:#x}, size: {exp_size:#x}")

    # Section headers
    f.seek(e_lfanew + 4 + 2)
    num_sec, = struct.unpack("<H", f.read(2))
    f.seek(e_lfanew + 4 + 16)
    opt_sz, = struct.unpack("<H", f.read(2))
    f.seek(e_lfanew + 4 + 20 + opt_sz)
    secs = []
    for _ in range(num_sec):
        sec = f.read(40)
        sname = sec[:8].decode(errors="ignore").strip("\x00")
        vsize, va, rsize, roff = struct.unpack("<IIII", sec[8:24])
        secs.append((sname, va, vsize, roff, rsize))

    def rva_to_file(r):
        for sname, va, vsize, roff, rsize in secs:
            if va <= r < va + vsize:
                return roff + (r - va)
        return None

    exp_file = rva_to_file(exp_rva)
    f.seek(exp_file)
    # IMAGE_EXPORT_DIRECTORY
    flags, ts, maj, minv, name_rva, base, num_funcs, num_names, funcs_rva, names_rva, ords_rva = struct.unpack("<IIHHIIIIIII", f.read(40))
    print(f"Export: num_funcs={num_funcs}, num_names={num_names}")

    names_file = rva_to_file(names_rva)
    funcs_file = rva_to_file(funcs_rva)
    ords_file = rva_to_file(ords_rva)

    func_list = []
    for i in range(num_names):
        f.seek(names_file + i * 4)
        nrva, = struct.unpack("<I", f.read(4))
        f.seek(rva_to_file(nrva))
        n = ""
        while True:
            ch = f.read(1)
            if not ch or ch == b"\x00": break
            n += chr(ch[0])
        
        f.seek(ords_file + i * 2)
        ord_val, = struct.unpack("<H", f.read(2))
        
        f.seek(funcs_file + ord_val * 4)
        frva, = struct.unpack("<I", f.read(4))
        func_list.append((frva, n))

    func_list.sort(key=lambda x: x[0])
    print(f"Sorted {len(func_list)} exported functions.")

    for r in rvas:
        # find nearest function <= r
        best = None
        for frva, name in func_list:
            if frva <= r:
                best = (frva, name)
            else:
                break
        if best:
            print(f"RVA {r:#x} is inside {best[1]} + {r - best[0]:#x} (func starts at {best[0]:#x})")
        else:
            print(f"RVA {r:#x} not found in exports")
