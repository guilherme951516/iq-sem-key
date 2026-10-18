"""Patch UI constants and re-seal the original VM; never runs downloaded Lua."""
import argparse
import base64
import hashlib
import json
import re
from pathlib import Path

from decode_vm import decode_vm, stream

MOD = 2**32
PATTERN = re.compile(r'(?P<table>\w+)\[(?P<index>\d+)\]=\{(?P<cf>\w+)="(?P<code>[^"]*)",(?P<kf>\w+)="(?P<constants>[^"]*)",(?P<pf>\w+)=(?P<params>\d+),(?P<sf>\w+)=(?P<seed>\d+),(?P<df>\w+)=false\}')


def patch(source_path, output_path, audit_path):
    source = source_path.read_text()
    original = decode_vm(source_path)
    alphabet = re.search(r'local \w+="([A-Za-z0-9/+]{64})"', source).group(1)
    standard = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    def unpack(value): return base64.b64decode(value.translate(str.maketrans(alphabet, standard)))
    def pack(value): return base64.b64encode(value).decode().translate(str.maketrans(standard, alphabet))
    matches = list(PATTERN.finditer(source))
    tail = source[matches[-1].end():]
    initial_hash = int(re.search(r'do local \w+=(\d+)%4294967296 for fi=', tail).group(1))
    key_match = re.search(r'local (\w+)=(\w+)\("([^"]+)"\)', tail)
    key_var, decode_function, encoded_key = key_match.groups()
    replacements = {
        b"https://raw.githubusercontent.com/checkurasshole/Script/main/IQ":
            b"https://raw.githubusercontent.com/guilherme951516/iq-sem-key/main/IQ.lua?v=20261018.2",
        b"https://keys.combowick.com": b"https://github.com/guilherme951516/iq-sem-key",
        b"Key required": b"Consultar disponibilidade",
        "Precisa de chave".encode(): b"Consultar disponibilidade",
        "Premium perk — unlock with a key".encode(): b"Personalize o tema do painel",
    }
    changes = []

    def checksum(all_matches):
        value = initial_hash
        for match in all_matches:
            for field in ("code", "constants"):
                for byte in unpack(match.group(field)):
                    value = (1664525 * value + byte + 1013904223) % MOD
                    value = value * (2 * byte + 1) % MOD
        return value

    old_hash = checksum(matches)

    def replace_prototype(match):
        encrypted = unpack(match.group("constants"))
        seed = (original["master_seed"] + int(match.group("seed")) + 2654435761) % MOD
        plain = bytes((a-b) % 256 for a, b in zip(encrypted, stream(seed, len(encrypted))))
        pos, rebuilt, changed = 0, bytearray(), False
        while pos < len(plain):
            kind = plain[pos]
            length = int.from_bytes(plain[pos+1:pos+4], "big")
            value = plain[pos+4:pos+4+length]
            pos += 4 + length
            if kind == 1:
                previous = value
                for before, after in replacements.items():
                    if before in value:
                        value = value.replace(before, after)
                if value != previous:
                    changes.append({"prototype": int(match.group("index")),
                        "before": previous.decode(errors="backslashreplace"),
                        "after": value.decode(errors="backslashreplace")})
                    changed = True
            rebuilt.append(kind)
            rebuilt.extend(len(value).to_bytes(3, "big"))
            rebuilt.extend(value)
        if not changed: return match.group(0)
        encrypted = bytes((a+b) % 256 for a, b in zip(rebuilt, stream(seed, len(rebuilt))))
        start = match.start("constants") - match.start()
        end = match.end("constants") - match.start()
        return match.group(0)[:start] + pack(encrypted) + match.group(0)[end:]

    result = PATTERN.sub(replace_prototype, source)
    new_hash = checksum(list(PATTERN.finditer(result)))
    key_bytes = unpack(encoded_key)
    adjusted = bytes(a ^ b ^ c for a, b, c in zip(key_bytes, stream(old_hash, len(key_bytes)), stream(new_hash, len(key_bytes))))
    key_pattern = re.compile(r'local ' + re.escape(key_var) + '=' + re.escape(decode_function) + r'\("[^"]+"\)')
    result, count = key_pattern.subn(lambda _: f'local {key_var}={decode_function}("{pack(adjusted)}")', result, count=1)
    assert count == 1 and changes
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("-- Visual fork for IQ / guilherme951516. Original: checkurasshole/combowick-loader.\n" + result)
    verified = decode_vm(output_path)
    assert verified["master_seed"] == original["master_seed"]
    assert len(verified["functions"]) == len(original["functions"])
    for before, after in zip(original["functions"], verified["functions"]):
        assert before["code"] == after["code"] and before["params"] == after["params"]
    audit_path.write_text(json.dumps({"source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
        "result_sha256": hashlib.sha256(output_path.read_bytes()).hexdigest(), "functions_verified": len(verified["functions"]),
        "instruction_bytes_unchanged": True, "changes": changes}, ensure_ascii=False, indent=2))
    print(json.dumps({"functions_verified": len(verified["functions"]), "constants_changed": len(changes)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("audit", type=Path)
    args = parser.parse_args()
    patch(args.source, args.output, args.audit)
