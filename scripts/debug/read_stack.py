import struct
import os

with open("dump.dmp", "rb") as f:
    f.seek(0x20)
    streams = [struct.unpack("<III", f.read(12)) for _ in range(12)]
    
    mods = []
    mem_ranges = []
    
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
        elif st_type == 9: # Memory64ListStream
            f.seek(rva)
            num_mem, base_rva = struct.unpack("<QQ", f.read(16))
            cur_rva = base_rva
            for _ in range(num_mem):
                va, sz = struct.unpack("<QQ", f.read(16))
                mem_ranges.append((va, sz, cur_rva))
                cur_rva += sz

    target_rsp = 0xe783ffedb0
    print(f"Searching memory for RSP={target_rsp:#x} among {len(mem_ranges)} ranges...")
    for va, sz, rva in mem_ranges:
        if va <= target_rsp < va + sz:
            print(f"Found memory range: {va:#x} - {va+sz:#x} at file offset {rva:#x}")
            f.seek(rva + (target_rsp - va))
            st_data = f.read(min(0x1000, sz - (target_rsp - va)))
            for i in range(0, len(st_data) - 8, 8):
                val, = struct.unpack("<Q", st_data[i:i+8])
                for m in mods:
                    if m["base"] <= val < m["base"] + m["size"]:
                        print(f"  [RSP+{i:#x}] = {val:#x} ({m['name']} + {val - m['base']:#x})")
            break
