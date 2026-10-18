"""Static decoder for the two supplied Lua VMs. Never executes Lua code."""

import argparse
import base64
import hashlib
import json
import re
from pathlib import Path


MOD = 2**32


def stream(seed, size):
    result = []
    for _ in range(size):
        seed = (1664525 * seed + 1013904223) % MOD
        result.append(((seed // 65536) + (seed % 65536) * 13) % 256)
    return result


def decode_vm(path):
    data = path.read_bytes()
    source = data.decode("utf-8")
    alphabet = re.search(r'local \w+="([A-Za-z0-9/+]{64})"', source).group(1)
    standard = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    def b64(value):
        return base64.b64decode(value.translate(str.maketrans(alphabet, standard)))

    pattern = r'\w+\[(\d+)\]=\{\w+="([^"]*)",\w+="([^"]*)",\w+=(\d+),\w+=(\d+),\w+=false\}'
    matches = list(re.finditer(pattern, source))
    functions = []
    for match in matches:
        index, code, constants, params, seed = match.groups()
        functions.append({"index": int(index), "code": b64(code),
                          "constants": b64(constants), "params": int(params),
                          "seed": int(seed)})
    assert [f["index"] for f in functions] == list(range(1, len(functions) + 1))
    tail = source[matches[-1].end():]
    seed = int(re.search(r'(\w+)=(\d+) \1=\(\1\*1000003', tail).group(2))
    encoded_key = b64(re.search(r'local \w+=\w+\("([^"]+)"\)', tail).group(1))
    triples = r'(\d+),(\d+),(\d+)'
    pairs = r'(\d+),(\d+)'
    dot = re.search(r'local _d=Vector3.new\(' + triples + r'\):Dot\(Vector3.new\(' + triples + r'\)\)', tail)
    nums = list(map(int, dot.groups()))
    dot_value = sum(a * b for a, b in zip(nums[:3], nums[3:]))
    cross = re.search(r'local _cv=Vector3.new\(' + triples + r'\):Cross\(Vector3.new\(' + triples + r'\)\)', tail)
    a, b, c, x, y, z = map(int, cross.groups())
    cross_square = (b*z-c*y)**2 + (c*x-a*z)**2 + (a*y-b*x)**2
    cf = re.search(r'local _cf=CFrame.new\(' + triples + r'\)\*CFrame.new\(' + triples + r'\)', tail)
    cf_sum = sum(map(int, cf.groups()))
    vv = re.search(r'local _vv=Vector2.new\(' + pairs + r'\)\+Vector2.new\(' + pairs + r'\)', tail)
    vv_sum = sum(map(int, vv.groups()))
    ts = re.search(r'local _ts=tostring\(Vector3.new\(' + triples + r'\)\)', tail)
    ts_sum = sum(", ".join(ts.groups()).encode("ascii"))
    for value in [dot_value, cross_square, cf_sum, vv_sum, ts_sum]:
        seed = (seed * 1000003 + value) % MOD
    hash_seed = int(re.search(r'do local \w+=(\d+)%4294967296 for fi=', tail).group(1))
    for fn in functions:
        for blob in [fn["code"], fn["constants"]]:
            for byte in blob:
                hash_seed = (1664525 * hash_seed + byte + 1013904223) % MOD
                hash_seed = (hash_seed * (2 * byte + 1)) % MOD
    key = [a ^ b ^ c for a, b, c in zip(encoded_key, stream(seed, len(encoded_key)),
                                       stream(hash_seed, len(encoded_key)))]
    master_seed = 2166136261
    for byte in key:
        master_seed = (master_seed * 257 + byte + 1) % MOD
    decoded = []
    for fn in functions:
        code = [(a-b) % 256 for a, b in zip(fn["code"], stream((master_seed + fn["seed"]) % MOD, len(fn["code"])))]
        blob = bytes((a-b) % 256 for a, b in zip(fn["constants"], stream((master_seed + fn["seed"] + 2654435761) % MOD, len(fn["constants"]))))
        constants = []
        pos = 0
        while pos < len(blob):
            assert pos + 4 <= len(blob)
            kind = blob[pos]
            length = int.from_bytes(blob[pos+1:pos+4], "big")
            pos += 4
            assert kind in (0, 1) and pos + length <= len(blob), (fn["index"], pos, length)
            value = blob[pos:pos+length].decode("utf-8", errors="surrogateescape")
            pos += length
            constants.append(float(value) if kind == 0 else value)
        decoded.append({"index": fn["index"], "params": fn["params"], "code": code, "constants": constants})
    return {"source": path.name, "sha256": hashlib.sha256(data).hexdigest(),
            "master_seed": master_seed, "functions": decoded}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = decode_vm(args.source)
    args.output.write_text(json.dumps(result, ensure_ascii=True, indent=2))
    print(json.dumps({"source": result["source"], "functions": len(result["functions"]),
                      "master_seed": result["master_seed"], "sha256": result["sha256"]}))
