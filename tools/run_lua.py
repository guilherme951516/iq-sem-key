"""Run trusted local Lua tests using the installed Lua 5.4 shared library."""
import argparse
import ctypes
import ctypes.util
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("files", nargs="+", type=Path)
parser.add_argument("--compile-only", action="store_true")
args = parser.parse_args()
lib = ctypes.CDLL(ctypes.util.find_library("lua5.4"))
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lib.luaL_loadfilex.restype = ctypes.c_int
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lib.lua_pcallk.restype = ctypes.c_int
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
for file in args.files:
    state = lib.luaL_newstate()
    try:
        lib.luaL_openlibs(state)
        status = lib.luaL_loadfilex(state, str(file).encode(), b"t")
        if not status and not args.compile_only:
            status = lib.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            message = lib.lua_tolstring(state, -1, None)
            raise SystemExit((message or b"Lua error").decode(errors="replace"))
        print(("COMPILED " if args.compile_only else "PASSED ") + str(file))
    finally:
        lib.lua_close(state)
