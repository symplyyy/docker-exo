#!/usr/bin/env bash
set -uo pipefail

URL="${URL:-http://api.localhost/health}"
RATE="${RATE:-100}"
DURATION="${1:-60}"

exec python3 - "$URL" "$RATE" "$DURATION" <<'PY'
import sys, time, threading, urllib.request
from concurrent.futures import ThreadPoolExecutor

url, rate, duration = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
ok = fail = 0
errors = {}
lock = threading.Lock()

def hit():
    global ok, fail
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            good = r.status == 200
            key = r.status
    except urllib.error.HTTPError as e:
        good, key = False, e.code
    except Exception as e:
        good, key = False, type(e).__name__
    with lock:
        if good:
            ok += 1
        else:
            fail += 1
            errors[key] = errors.get(key, 0) + 1

start = time.time()
with ThreadPoolExecutor(max_workers=50) as pool:
    n = 0
    while time.time() - start < duration:
        pool.submit(hit)
        n += 1
        time.sleep(max(0, start + n / rate - time.time()))
        if n % (rate * 5) == 0:
            print(f"{int(time.time() - start):>4}s  ok={ok} échecs={fail}", flush=True)

print(f"total={ok + fail} ok={ok} échecs={fail} {errors if errors else ''}")
sys.exit(1 if fail else 0)
PY
