import struct
import os

with open("dump.dmp", "rb") as f:
    f.seek(0x20)
    streams = [struct.unpack("<III", f.read(12)) for _ in range(12)]
    
    mods = []
    mem_ranges = []
    threads = []
    
    for st_type, size, rva in streams:
        if st_type == 4:
            f.seek(rva)
            num_mods, = struct.unpack("<I", f.read(4))
            for _ in range(num_mods):
                base_addr, mod_size, chk, ts, name_rva, vs, cv_sz, cv_rva, misc_sz, misc_rva, r1, r2 = struct.unpack("<QIIII52sIIIIQQ", f.read(108))
                cur = f.tell()
                f.seek(name_rva)
                nlen, = struct.unpack("<I", f.read(4))
                name = f.read(nlen).decode("utf-16le", errors="ignore").rstrip("\x00")
                f.seek(cur)
                mods.append({"name": os.path.basename(name), "base": base_addr, "size": mod_size})
        elif st_type == 9:
            f.seek(rva)
            num_mem, base_rva = struct.unpack("<QQ", f.read(16))
            cur_rva = base_rva
            for _ in range(num_mem):
                va, sz = struct.unpack("<QQ", f.read(16))
                mem_ranges.append((va, sz, cur_rva))
                cur_rva += sz
        elif st_type == 3:
            f.seek(rva)
            num_threads, = struct.unpack("<I", f.read(4))
            for _ in range(num_threads):
                tid, susp, prioc, prio, teb, st_va, st_sz, st_rva, ctx_sz, ctx_rva = struct.unpack("<IIIIQQIIII", f.read(48))
                threads.append({
                    "tid": tid, "teb": teb, "ctx_rva": ctx_rva, "ctx_sz": ctx_sz
                })

    def read_mem(target_va, num_bytes):
        for va, sz, rva in mem_ranges:
            if va <= target_va < va + sz:
                f.seek(rva + (target_va - va))
                return f.read(min(num_bytes, sz - (target_va - va)))
        return None

    def find_mod(addr):
        for m in mods:
            if m["base"] <= addr < m["base"] + m["size"]:
                return f"{m['name']}+{addr - m['base']:#x}"
        return f"{addr:#x}"

    for t in threads:
        f.seek(t["ctx_rva"])
        ctx = f.read(t["ctx_sz"])
        rip, = struct.unpack("<Q", ctx[0xF8:0x100])
        rsp, = struct.unpack("<Q", ctx[0x98:0xA0])
        print(f"\n--- Thread 0x{t['tid']:x} ({t['tid']}) RIP={find_mod(rip)} RSP={rsp:#x} ---")
        
        # Read stack
        st_bytes = read_mem(rsp, 0x180)
        if st_bytes:
            for off in range(0, len(st_bytes) - 8, 8):
                val, = struct.unpack("<Q", st_bytes[off:off+8])
                for m in mods:
                    if m["base"] <= val < m["base"] + m["size"]:
                        # only print our modules
                        if "aa_roas" in m["name"].lower():
                            print(f"  [RSP+{off:#x}] {m['name']}+{val - m['base']:#x}")
