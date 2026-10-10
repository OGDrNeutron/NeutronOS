#!/usr/bin/env python3
"""Create/verify NeutronOS Ed25519 release envelopes without exposing keys."""
import argparse, base64, ctypes, ctypes.util, hashlib, json, os, pathlib, tempfile

PREFIX = "NEUTRONOS-ED25519-SECRET:"

def sodium():
    lib = ctypes.cdll.LoadLibrary(ctypes.util.find_library("sodium"))
    if lib.sodium_init() < 0: raise SystemExit("libsodium initialization failed")
    return lib

def atomic(path, data, mode=0o644):
    path = pathlib.Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="."+path.name+".", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as f: f.write(data)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def load_secret(path):
    text = pathlib.Path(path).read_text().strip()
    if not text.startswith(PREFIX): raise SystemExit("unsupported signing credential")
    key = base64.b64decode(text[len(PREFIX):], validate=True)
    if len(key) != 64: raise SystemExit("invalid Ed25519 secret key")
    return key

def public_for(secret):
    lib=sodium(); public=(ctypes.c_ubyte*32)(); sec=(ctypes.c_ubyte*64).from_buffer_copy(secret)
    if lib.crypto_sign_ed25519_sk_to_pk(public, sec): raise SystemExit("public-key derivation failed")
    return bytes(public)

def generate(args):
    path=pathlib.Path(args.key)
    if path.exists():
        secret=load_secret(path)
    else:
        lib=sodium(); public=(ctypes.c_ubyte*32)(); sec=(ctypes.c_ubyte*64)()
        if lib.crypto_sign_keypair(public,sec): raise SystemExit("key generation failed")
        secret=bytes(sec); atomic(path,(PREFIX+base64.b64encode(secret).decode()+"\n").encode(),0o600)
    os.chmod(path,0o600)
    pathlib.Path(args.public).write_text("NEUTRONOS-ED25519:"+base64.b64encode(public_for(secret)).decode()+"\n")

def sign(args):
    secret=load_secret(args.key); payload=pathlib.Path(args.payload).read_bytes(); lib=sodium()
    sig=(ctypes.c_ubyte*64)(); siglen=ctypes.c_ulonglong()
    lib.crypto_sign_detached(sig,ctypes.byref(siglen),(ctypes.c_ubyte*len(payload)).from_buffer_copy(payload),len(payload),(ctypes.c_ubyte*64).from_buffer_copy(secret))
    signature=bytes(sig)
    envelope={"format":"neutronos.update-manifest.v2","signedPayload":base64.b64encode(payload).decode(),"signature":base64.b64encode(signature).decode()}
    atomic(args.output,(json.dumps(envelope,indent=2,sort_keys=True)+"\n").encode())
    atomic(args.signature,base64.b64encode(signature)+b"\n")

def verify(args):
    env=json.loads(pathlib.Path(args.envelope).read_text()); payload=base64.b64decode(env["signedPayload"]); sig=base64.b64decode(env["signature"])
    pubtext=pathlib.Path(args.public).read_text().strip(); pub=base64.b64decode(pubtext.split(":",1)[1]); lib=sodium()
    rc=lib.crypto_sign_verify_detached((ctypes.c_ubyte*64).from_buffer_copy(sig),(ctypes.c_ubyte*len(payload)).from_buffer_copy(payload),len(payload),(ctypes.c_ubyte*32).from_buffer_copy(pub))
    if rc: raise SystemExit("signature verification failed")
    print("signature verified")

p=argparse.ArgumentParser(); s=p.add_subparsers(dest="cmd",required=True)
g=s.add_parser("generate"); g.add_argument("--key",required=True); g.add_argument("--public",required=True); g.set_defaults(fn=generate)
q=s.add_parser("sign"); q.add_argument("--key",required=True); q.add_argument("--payload",required=True); q.add_argument("--output",required=True); q.add_argument("--signature",required=True); q.set_defaults(fn=sign)
v=s.add_parser("verify"); v.add_argument("--envelope",required=True); v.add_argument("--public",required=True); v.set_defaults(fn=verify)
a=p.parse_args(); a.fn(a)
