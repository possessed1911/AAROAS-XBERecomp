import struct

with open('assets/default.xbe', 'rb') as f:
    xbe = f.read()

magic, sig, base, size_headers, size_image = struct.unpack_from('<4s256sIII', xbe, 0)
num_sections, sect_hdr_off = struct.unpack_from('<II', xbe, 0x11C)

def get_bytes(addr, count):
    for i in range(num_sections):
        s_off = sect_hdr_off - base + i * 56
        flags, virt_addr, virt_sz, raw_off, raw_sz, name_addr, ref_cnt = struct.unpack_from('<IIIIIII', xbe, s_off)
        if virt_addr <= addr < virt_addr + virt_sz:
            file_off = raw_off + (addr - virt_addr)
            return xbe[file_off:file_off+count]
    return None

for addr in range(0x000EE000, 0x000F0000, 4):
    b = get_bytes(addr, 4)
    if b:
        val, = struct.unpack('<I', b)
        s_bytes = get_bytes(val, 64)
        if s_bytes and all(32 <= c <= 126 for c in s_bytes[:6]) and b'\x00' in s_bytes:
            idx = s_bytes.index(b'\x00')
            if idx >= 4:
                s = s_bytes[:idx].decode('ascii', errors='ignore')
                print(f'{hex(addr)} -> {hex(val)}: "{s}"')
