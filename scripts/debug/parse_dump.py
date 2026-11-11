import struct
import os

with open("dump.dmp", "rb") as f:
    sig, ver, num_streams, stream_dir_rva, checksum, time_date_stamp, flags = struct.unpack("<4sIIIIQI", f.read(32))
    print(f"Header: sig={sig}, streams={num_streams}, dir_rva={stream_dir_rva:#x}")

    f.seek(stream_dir_rva)
    streams = []
    for _ in range(num_streams):
        st_type, data_size, rva = struct.unpack("<III", f.read(12))
        streams.append((st_type, data_size, rva))

    threads = []
    modules = []
    for st_type, size, rva in streams:
        if st_type == 3: # ThreadListStream
            f.seek(rva)
            num_threads, = struct.unpack("<I", f.read(4))
            for _ in range(num_threads):
                tid, susp, prioc, prio, teb, st_va, st_sz, st_rva, ctx_sz, ctx_rva = struct.unpack("<IIIIQQIIII", f.read(48))
                threads.append({
                    "tid": tid, "teb": teb, "stack_va": st_va, "stack_sz": st_sz, "ctx_rva": ctx_rva, "ctx_sz": ctx_sz
                })
        elif st_type == 4: # ModuleListStream
            f.seek(rva)
            num_mods, = struct.unpack("<I", f.read(4))
            for _ in range(num_mods):
                base_addr, mod_size, chk, ts, name_rva, vs, cv_sz, cv_rva, misc_sz, misc_rva, r1, r2 = struct.unpack("<QIIII52sIIIIQQ", f.read(108))
                cur = f.tell()
                f.seek(name_rva)
                nlen, = struct.unpack("<I", f.read(4))
                name = f.read(nlen).decode("utf-16le", errors="ignore").rstrip("\x00")
                f.seek(cur)
                modules.append({"name": name, "base": base_addr, "size": mod_size})

    print(f"Loaded {len(modules)} modules and {len(threads)} threads.")
    for m in modules:
        if "aa_roas" in m["name"].lower():
            print(f"Module: {m['name']} Base: {m['base']:#x} Size: {m['size']:#x}")

    for t in threads:
        f.seek(t["ctx_rva"])
        ctx_bytes = f.read(t["ctx_sz"])
        if len(ctx_bytes) >= 0x100:
            rip, = struct.unpack("<Q", ctx_bytes[0xF8:0x100])
            rsp, = struct.unpack("<Q", ctx_bytes[0x98:0xA0])
            rcx, = struct.unpack("<Q", ctx_bytes[0x80:0x88])
            rdx, = struct.unpack("<Q", ctx_bytes[0x88:0x90])
            rbx, = struct.unpack("<Q", ctx_bytes[0x90:0x98])
            rax, = struct.unpack("<Q", ctx_bytes[0x78:0x80])
            
            mod_name = "unknown"
            offset = 0
            for m in modules:
                if m["base"] <= rip < m["base"] + m["size"]:
                    mod_name = os.path.basename(m["name"])
                    offset = rip - m["base"]
                    break
            print(f"Thread {t['tid']:x}: RIP={rip:#x} ({mod_name}+{offset:#x}) RSP={rsp:#x} RAX={rax:#x}")
