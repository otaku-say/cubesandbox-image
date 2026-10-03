#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""aiod v2 API 全量测试 —— 通用请求工具与断言收集。

用法：BASE=<网关基址> python3 suite.py
  例：BASE="https://<proxy-host>/sandbox/<sid>/8080" python3 suite.py
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("BASE", "").rstrip("/")
TIMEOUT = float(os.environ.get("HTTP_TIMEOUT", "60"))

PASS, FAIL, SKIP = [], [], []


def _req(method, path, body=None, params=None, raw=False, headers=None, timeout=None):
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = None
    hdrs = dict(headers or {})
    if body is not None:
        if isinstance(body, (bytes, bytearray)):
            data = bytes(body)
            hdrs.setdefault("Content-Type", "application/octet-stream")
        else:
            data = json.dumps(body).encode()
            hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout or TIMEOUT) as resp:
            payload = resp.read()
            dt = (time.time() - t0) * 1000
            if raw:
                return resp.status, payload, dt
            try:
                return resp.status, json.loads(payload), dt
            except Exception:
                return resp.status, payload, dt
    except urllib.error.HTTPError as e:
        dt = (time.time() - t0) * 1000
        payload = e.read()
        try:
            return e.code, json.loads(payload), dt
        except Exception:
            return e.code, payload, dt


def get(path, params=None, raw=False, **kw):
    return _req("GET", path, params=params, raw=raw, **kw)


def post(path, body=None, raw=False, **kw):
    return _req("POST", path, body=body, raw=raw, **kw)


def put(path, body=None, raw=False, **kw):
    return _req("PUT", path, body=body, raw=raw, **kw)


def patch(path, body=None, raw=False, **kw):
    return _req("PATCH", path, body=body, raw=raw, **kw)


def delete(path, body=None, **kw):
    return _req("DELETE", path, body=body, **kw)


def case(name, ok, detail=""):
    """记录一个测试用例结果。"""
    if ok:
        PASS.append(name)
        print(f"  \u2714 {name}" + (f"  [{detail}]" if detail else ""))
    else:
        FAIL.append((name, detail))
        print(f"  \u2718 {name}  {detail}")
    return ok


def skip(name, detail=""):
    SKIP.append((name, detail))
    print(f"  \u2298 {name}  {detail}" if detail else f"  \u2298 {name}")


def section(title):
    print(f"\n[{title}]")


def summary():
    print("\n" + "=" * 64)
    print(f"通过 {len(PASS)} | 失败 {len(FAIL)} | 跳过 {len(SKIP)}")
    if FAIL:
        print("失败明细：")
        for n, d in FAIL:
            print(f"  - {n}: {d}")
    return 0 if not FAIL else 1


def unwrap(resp):
    """成功响应 → data 部分；失败 → None（同时返回原始响应便于诊断）。"""
    status, body, _ = resp
    if isinstance(body, dict) and body.get("success") is True:
        return body.get("data")
    return None


def envelope_ok(resp):
    status, body, _ = resp
    return status == 200 and isinstance(body, dict) and body.get("success") is True
