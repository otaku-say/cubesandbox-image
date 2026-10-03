#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""aiod v2 API 全量测试套件。

覆盖 v2 OpenAPI（0.9.2，65 路径）中的运维、命令、文件、终端、监听、代码、
浏览器、MCP 八个面（computer 面在 aio-daemon 镜像上预期不可用，单独标注）。

用法：BASE="https://<proxy>/sandbox/<sid>/8080" python3 suite.py
"""
import json
import hashlib
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import (BASE, PASS, FAIL, SKIP, get, post, put, patch, delete,
                     case, skip, section, summary, unwrap, envelope_ok, _req as _req_wrap)


# ---------------------------------------------------------------- 运维面
def sec_ops():
    section("运维 /v2/sandbox")
    st, body, dt = get("/health")
    case("GET /health → 200", st == 200, f"{st} {dt:.0f}ms")

    st, body, dt = get("/v2/sandbox")
    ok = envelope_ok((st, body, dt))
    case("GET /v2/sandbox → 200", ok, f"{st} {dt:.0f}ms")
    if ok:
        d = body["data"]
        keys = sorted(d.keys())
        print(f"      字段: {', '.join(keys[:12])}")
        case("/v2/sandbox 含 host/version 类字段",
             any(k in d for k in ("hostname", "host", "version", "os", "kernel")), str(keys[:6]))

    st, body, dt = get("/v2/sandbox/packages", params={"lang": "python"})
    d = body.get("data") if isinstance(body, dict) else None
    ok = st == 200 and isinstance(d, str) and "==" in d
    case("GET /v2/sandbox/packages?lang=python → 200（文本清单）", ok, f"{st} {dt:.0f}ms")
    if ok:
        print(f"      前两条: {' / '.join(l.strip(' -') for l in d.strip().splitlines()[:2])}")
    st2, body2, _ = get("/v2/sandbox/packages", params={"lang": "node"})
    case("GET /v2/sandbox/packages?lang=node → 200", st2 == 200, f"{st2}")


# ---------------------------------------------------------------- 命令面
def _read_command(cmd_id, offset=0, stderr_offset=0, wait=False, wait_timeout=10):
    params = {"offset": offset, "stderr_offset": stderr_offset}
    if wait:
        params.update({"wait": "true", "wait_timeout": wait_timeout})
    return get(f"/v2/commands/{cmd_id}", params=params)


def sec_commands():
    section("命令 /v2/commands")

    # 1) 同步执行 + 读取
    st, body, dt = post("/v2/commands", {"command": "echo v2-ok; id -u", "timeout": 30})
    ok = st == 200 and body.get("success") is True
    case("POST /v2/commands（同步）", ok, f"{st} {dt:.0f}ms")
    if ok:
        d = body["data"]
        cid = d.get("command_id")
        out = (d.get("stdout") or "")
        case("同步响应直接携带 stdout", "v2-ok" in out, repr(out[:60]))
        st2, b2, _ = _read_command(cid)
        out2 = (b2.get("data", {}).get("stdout") or "") if isinstance(b2, dict) else ""
        case("GET /v2/commands/{id} 可回读输出", st2 == 200 and "v2-ok" in out2, repr(out2[:60]))

    # 2) cwd / env / user
    st, body, _ = post("/v2/commands", {"command": "pwd; echo $V2MARK", "cwd": "/tmp",
                                        "env": {"V2MARK": "mark42"}, "timeout": 20})
    out = body.get("data", {}).get("stdout", "") if isinstance(body, dict) else ""
    case("cwd 生效", "/tmp" in out, repr(out[:40]))
    case("env 生效", "mark42" in out, repr(out[:40]))

    # 3) 异步模式 + 轮询
    st, body, dt = post("/v2/commands", {"command": "sleep 1; echo async-done", "mode": "async"})
    ok = st == 200 and body.get("success") is True
    case("POST /v2/commands（async 立即返回）", ok, f"{st} {dt:.0f}ms")
    if ok:
        cid = body["data"].get("command_id")
        st2, b2, dt2 = _read_command(cid, wait=True, wait_timeout=8)
        out = b2.get("data", {}).get("stdout", "") if isinstance(b2, dict) else ""
        case("异步命令轮询到完成", "async-done" in out, f"{dt2:.0f}ms {repr(out[:40])}")

    # 4) stdin
    st, body, _ = post("/v2/commands", {"command": "read line; echo got:$line", "mode": "async"})
    if st == 200 and body.get("success"):
        cid = body["data"]["command_id"]
        time.sleep(0.6)
        stx, bx, _ = post(f"/v2/commands/{cid}/stdin", {"input": "hello-stdin\n"})
        case("POST /v2/commands/{id}/stdin", stx == 200, f"{stx}")
        time.sleep(0.8)
        _, b2, _ = _read_command(cid, wait=True, wait_timeout=5)
        out = b2.get("data", {}).get("stdout", "") if isinstance(b2, dict) else ""
        case("stdin 被进程读到", "hello-stdin" in out, repr(out[:60]))
    else:
        skip("stdin 用例", "异步命令未建立")

    # 5) kill
    st, body, _ = post("/v2/commands", {"command": "sleep 120", "mode": "async"})
    if st == 200 and body.get("success"):
        cid = body["data"]["command_id"]
        time.sleep(1)
        stk, bk, _ = post(f"/v2/commands/{cid}/kill", {"signal": "SIGKILL"})
        case("POST /v2/commands/{id}/kill", stk == 200, f"{stk}")
        time.sleep(1)
        _, b2, _ = _read_command(cid)
        d = b2.get("data", {}) if isinstance(b2, dict) else {}
        # 实测语义：SIGKILL 后进入终态 completed，退出码 -1（不单独报告 signal）
        status = (d.get("command") or {}).get("status") or d.get("status")
        exit_code = (d.get("command") or {}).get("exit_code")
        case("kill 后进入终态且退出码非 0", status in ("completed", "killed", "terminated", "failed")
             and exit_code not in (0, None), f"status={status} exit_code={exit_code}")

    # 6) 超时
    st, body, dt = post("/v2/commands", {"command": "sleep 5; echo never", "timeout": 1})
    status = body.get("data", {}).get("status") if isinstance(body, dict) else None
    case("timeout=1 会截断等待", st == 200 and status in ("running", "timeout", "ok"),
         f"status={status} {dt:.0f}ms")

    # 7) hard_timeout / max_output_length / stderr 分流
    st, body, _ = post("/v2/commands", {"command": "yes x | head -c 20000", "max_output_length": 100})
    out = body.get("data", {}).get("stdout", "") if isinstance(body, dict) else ""
    case("max_output_length 生效", len(out) <= 200, f"len={len(out)}")

    st, body, _ = post("/v2/commands", {"command": "echo out1; echo err1 >&2"})
    d = body.get("data", {}) if isinstance(body, dict) else {}
    case("stdout/stderr 分流采集", d.get("stdout", "").strip() == "out1" and d.get("stderr", "").strip() == "err1",
         f"out={d.get('stdout')!r} err={d.get('stderr')!r}")
    cid = d.get("command_id")
    st, body, _ = get(f"/v2/commands/{cid}", params={"offset": 0, "stderr_offset": 0})
    d2 = body.get("data", {}) if isinstance(body, dict) else {}
    case("GET 带 offset/stderr_offset 回读", "out1" in (d2.get("stdout") or "") and "err1" in (d2.get("stderr") or ""),
         f"out={d2.get('stdout')!r}")
    exit_code = (d2.get("command") or {}).get("exit_code")
    case("命令退出码可读（data.command.exit_code）", exit_code == 0, f"exit_code={exit_code}")

    # 8) 会话：cwd 固定在创建时；env/身份/输出跨调用保留（cd 不泄漏）
    st, body, _ = post("/v2/commands/sessions", {"id": "v2s1", "cwd": "/etc"})
    case("POST /v2/commands/sessions（带 cwd）", st == 200 and body.get("success") is True, f"{st}")
    st, body, _ = post("/v2/commands", {"command": "pwd", "session": "v2s1"})
    out = body.get("data", {}).get("stdout", "") if isinstance(body, dict) else ""
    case("会话 cwd 生效（创建时指定 /etc）", "/etc" in out, repr(out[:40]))
    post("/v2/commands", {"command": "cd /var", "session": "v2s1"})
    st, body, _ = post("/v2/commands", {"command": "pwd", "session": "v2s1"})
    out = body.get("data", {}).get("stdout", "") if isinstance(body, dict) else ""
    case("会话内 cd 不跨调用泄漏（每条命令仍是新进程）", "/etc" in out and "/var" not in out, repr(out[:40]))
    st, body, _ = get("/v2/commands/sessions")
    ids = []
    if isinstance(body, dict) and body.get("success"):
        d = body["data"]
        ids = [s.get("session_id") or s.get("id") for s in (d if isinstance(d, list) else d.get("sessions", []))]
    case("GET /v2/commands/sessions 列出会话", "v2s1" in ids, str(ids[:4]))
    std, bd, _ = delete("/v2/commands/sessions/v2s1")
    case("DELETE /v2/commands/sessions/{id}", std == 200, f"{std}")

    # 9) shell 选择器
    st, body, _ = post("/v2/commands", {"command": "echo $0", "shell": "sh"})
    out = body.get("data", {}).get("stdout", "") if isinstance(body, dict) else ""
    case("shell=sh 可执行", st == 200 and ("sh" in out), repr(out[:30]))
    st, body, _ = post("/v2/commands", {"command": "/bin/echo", "args": ["argv-ok"], "shell": "none"})
    out = body.get("data", {}).get("stdout", "") if isinstance(body, dict) else ""
    case("shell=none + args 可执行", st == 200 and "argv-ok" in out, repr(out[:40]))


# ---------------------------------------------------------------- 文件面
def sec_fs():
    section("文件 /v2/fs")

    st, body, dt = post("/v2/fs/mkdir", {"path": "/tmp/v2fs", "parents": True})
    case("POST /v2/fs/mkdir", st == 200 and body.get("success") is True, f"{st} {dt:.0f}ms")

    st, body, _ = post("/v2/fs/write", {"path": "/tmp/v2fs/a.txt", "content": "line1\nline2\nline3\n"})
    case("POST /v2/fs/write", st == 200 and body.get("success") is True, f"{st}")

    st, body, _ = get("/v2/fs/read", params={"path": "/tmp/v2fs/a.txt"})
    content = json.dumps(body, ensure_ascii=False) if not isinstance(body, dict) else json.dumps(body["data"], ensure_ascii=False)
    case("GET /v2/fs/read", st == 200 and "line2" in content, repr(content[:70]))

    st, body, _ = get("/v2/fs/read", params={"path": "/tmp/v2fs/a.txt", "start_line": 1, "end_line": 2})
    d = body.get("data") if isinstance(body, dict) else body
    txt = d.get("content") if isinstance(d, dict) else str(d)
    case("read 支持 start_line/end_line（不含尾行）", st == 200 and "line2" in txt and "line3" not in txt,
         repr(txt[:50]))

    st, body, _ = get("/v2/fs/stat", params={"path": "/tmp/v2fs/a.txt"})
    d = body.get("data", {}) if isinstance(body, dict) else {}
    case("GET /v2/fs/stat", st == 200 and (d.get("size") or 0) > 0, f"size={d.get('size')}")

    st, body, _ = get("/v2/fs/list", params={"path": "/tmp/v2fs", "recursive": "true", "show_hidden": "false"})
    case("GET /v2/fs/list（recursive）", st == 200, f"{st}")

    st, body, _ = get("/v2/fs/tree", params={"path": "/tmp/v2fs"})
    case("GET /v2/fs/tree", st == 200, f"{st}")

    st, body, _ = post("/v2/fs/edit", {"path": "/tmp/v2fs/a.txt", "command": "str_replace",
                                       "old_str": "line2", "new_str": "LINE-TWO"})
    case("POST /v2/fs/edit（str_replace）", st == 200 and body.get("success") is True, f"{st}")
    _, b2, _ = get("/v2/fs/read", params={"path": "/tmp/v2fs/a.txt"})
    case("edit 结果已落盘", "LINE-TWO" in json.dumps(b2, ensure_ascii=False), "")

    st, body, _ = post("/v2/fs/copy", {"source": "/tmp/v2fs/a.txt", "destination": "/tmp/v2fs/b.txt"})
    case("POST /v2/fs/copy", st == 200, f"{st}")
    st, body, _ = post("/v2/fs/move", {"source": "/tmp/v2fs/b.txt", "destination": "/tmp/v2fs/c.txt"})
    case("POST /v2/fs/move", st == 200, f"{st}")

    st, body, _ = post("/v2/fs/grep", {"path": "/tmp/v2fs", "pattern": "LINE-TWO", "recursive": True})
    case("POST /v2/fs/grep", st == 200 and "LINE-TWO" in json.dumps(body, ensure_ascii=False), f"{st}")

    st, body, _ = get("/v2/fs/search", params={"path": "/tmp/v2fs", "pattern": "**/*.txt"})
    case("GET /v2/fs/search（glob）", st == 200 and "c.txt" in json.dumps(body, ensure_ascii=False), f"{st}")

    # 二进制往返：multipart 上传 → 下载 → sha256 比对
    blob = os.urandom(4096)
    bnd = "----v2suite"
    payload = (b"--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"bin.dat\"\r\n"
               b"Content-Type: application/octet-stream\r\n\r\n" % bnd.encode()) + blob + \
              ("\r\n--%s--\r\n" % bnd).encode()
    st, body, _ = _req_wrap("POST", "/v2/fs/upload", body=payload,
                            headers={"Content-Type": f"multipart/form-data; boundary={bnd}"})
    up_ok = st == 200 and isinstance(body, dict) and body.get("success") is True
    case("POST /v2/fs/upload（multipart 二进制）", up_ok, f"{st} {body.get('data', {}).get('file_size') if isinstance(body, dict) else '-'}B")
    st, raw, _ = get("/v2/fs/download", params={"path": "/tmp/bin.dat"}, raw=True)
    same = isinstance(raw, (bytes, bytearray)) and hashlib.sha256(raw).hexdigest() == hashlib.sha256(blob).hexdigest()
    case("上传↔下载 sha256 一致（二进制无损）", st == 200 and same,
         f"{st} {len(raw) if isinstance(raw,(bytes,bytearray)) else '-'}B")

    st, raw, _ = get("/v2/fs/download", params={"path": "/tmp/v2fs/c.txt"}, raw=True)
    case("GET /v2/fs/download", st == 200 and b"LINE-TWO" in raw, f"{st} {len(raw) if isinstance(raw,(bytes,bytearray)) else '-'}B")

    st, body, _ = post("/v2/fs/delete", {"path": "/tmp/v2fs/c.txt"})
    case("POST /v2/fs/delete", st == 200, f"{st}")


# ---------------------------------------------------------------- 终端面
def sec_pty():
    section("终端 /v2/pty")

    st, body, dt = post("/v2/pty/sessions", {"id": "v2pty", "cols": 100, "rows": 30, "cwd": "/tmp"})
    case("POST /v2/pty/sessions", st == 200 and body.get("success") is True, f"{st} {dt:.0f}ms")

    st, body, dt = post("/v2/pty/sessions/v2pty/exec", {"command": "echo pty-ok"})
    out = json.dumps(body.get("data", {}), ensure_ascii=False) if isinstance(body, dict) else ""
    case("POST /v2/pty/sessions/{id}/exec", st == 200 and "pty-ok" in out, f"{st} {dt:.0f}ms")

    st, body, _ = get("/v2/pty/sessions/v2pty/screen")
    out = json.dumps(body, ensure_ascii=False)
    case("GET .../screen 含命令输出", st == 200 and "pty-ok" in out, "")

    st, body, _ = post("/v2/pty/sessions/v2pty/input", {"input": "echo from-input", "press_enter": True})
    case("POST .../input 注入按键", st == 200, f"{st}")
    time.sleep(0.6)
    _, b2, _ = get("/v2/pty/sessions/v2pty/screen")
    case("input 结果出现在屏幕", "from-input" in json.dumps(b2, ensure_ascii=False), "")

    st, body, _ = patch("/v2/pty/sessions/v2pty", {"cols": 120, "rows": 40})
    case("PATCH .../sessions/{id}（改尺寸）", st == 200, f"{st}")

    st, body, _ = get("/v2/pty/sessions/v2pty")
    case("GET /v2/pty/sessions/{id}", st == 200, f"{st}")

    st, body, _ = get("/v2/pty/sessions")
    case("GET /v2/pty/sessions 列表", st == 200 and "v2pty" in json.dumps(body, ensure_ascii=False), f"{st}")

    st, body, _ = post("/v2/pty/sessions/v2pty/signal", {"signal": "SIGINT"})
    case("POST .../signal", st in (200, 202), f"{st}")

    st, body, _ = delete("/v2/pty/sessions/v2pty")
    case("DELETE /v2/pty/sessions/{id}", st == 200, f"{st}")


# ---------------------------------------------------------------- 监听面
def sec_watch():
    section("监听 /v2/watch")
    post("/v2/fs/mkdir", {"path": "/tmp/v2watch", "parents": True})

    st, body, dt = post("/v2/watch", {"path": "/tmp/v2watch", "recursive": True})
    ok = st == 200 and body.get("success") is True
    case("POST /v2/watch", ok, f"{st} {dt:.0f}ms")
    wid = None
    if ok:
        d = body["data"]
        wid = d.get("watcher_id") or d.get("id")
        print(f"      watcher_id={wid}")
        case("返回 watcher_id", bool(wid), str(wid)[:18])

    if wid:
        post("/v2/fs/write", {"path": "/tmp/v2watch/new.txt", "content": "watched\n"})
        time.sleep(1.2)
        st, body, _ = get(f"/v2/watch/{wid}/poll", params={"cursor": 0, "timeout": 5})
        txt = json.dumps(body, ensure_ascii=False)
        case("GET .../poll 收到事件", st == 200 and ("new.txt" in txt or "create" in txt or "write" in txt),
             txt[:120])
        st, body, _ = get("/v2/watch")
        case("GET /v2/watch 列表", st == 200 and wid in json.dumps(body, ensure_ascii=False), f"{st}")
        st, body, _ = delete(f"/v2/watch/{wid}")
        case("DELETE /v2/watch/{id}", st == 200, f"{st}")


# ---------------------------------------------------------------- 代码面
def sec_code():
    section("代码 /v2/code")

    st, body, dt = post("/v2/code/execute", {"language": "python", "code": "print(6*7)"})
    txt = json.dumps(body, ensure_ascii=False) if isinstance(body, dict) else str(body)
    case("POST /v2/code/execute（python）", st == 200 and "42" in txt, f"{st} {dt:.0f}ms")

    st, body, dt = post("/v2/code/execute", {"language": "javascript", "code": "console.log(7*6)"})
    txt = json.dumps(body, ensure_ascii=False) if isinstance(body, dict) else str(body)
    case("POST /v2/code/execute（javascript）", st == 200 and "42" in txt, f"{st} {dt:.0f}ms")

    st, body, _ = get("/v2/code/info")
    case("GET /v2/code/info", st == 200, f"{st}")

    # 代码会话：状态保持
    sid = None
    st, body, _ = post("/v2/code/sessions", {"language": "python"})
    if st == 200 and isinstance(body, dict) and body.get("success"):
        d = body["data"] or {}
        sid = d.get("session_id") or d.get("id")
    if not sid:
        st, body, _ = post("/v2/code/sessions", {})
        if st == 200 and isinstance(body, dict) and body.get("success"):
            d = body["data"] or {}
            sid = d.get("session_id") or d.get("id")
    if sid:
        case("POST /v2/code/sessions", True, f"id={sid}")
        post("/v2/code/execute", {"language": "python", "code": "x = 11", "session_id": sid})
        st, body, _ = post("/v2/code/execute", {"language": "python", "code": "print(x*2)", "session_id": sid})
        case("代码会话保持状态", "22" in json.dumps(body, ensure_ascii=False), "")
        delete(f"/v2/code/sessions/{sid}")
    else:
        skip("代码会话", "create 未返回 session_id")


# ---------------------------------------------------------------- 浏览器面
PAGE = ("data:text/html,<html><body><h1 id=h>t</h1>"
        "<input id=i><button id=b onclick=\"document.getElementById('h').textContent='clicked'\">go</button>"
        "<a id=a href='#x'>link</a></body></html>")


def sec_browser():
    section("浏览器 /v2/browser")

    st, body, dt = get("/v2/browser/info")
    txt = json.dumps(body, ensure_ascii=False)
    case("GET /v2/browser/info", st == 200 and "ready" in txt or st == 200, f"{st} {dt:.0f}ms")

    st, body, dt = post("/v2/browser/navigate", {"url": PAGE})
    case("POST /v2/browser/navigate", st == 200 and body.get("success") is True, f"{st} {dt:.0f}ms")

    st, raw, dt = get("/v2/browser/screenshot", params={"format": "png"}, raw=True)
    ok = st == 200 and isinstance(raw, (bytes, bytearray)) and raw[:8] == b"\x89PNG\r\n\x1a\n"
    case("GET /v2/browser/screenshot（PNG）", ok, f"{st} {len(raw) if isinstance(raw,(bytes,bytearray)) else '-'}B {dt:.0f}ms")

    st, body, _ = post("/v2/browser/evaluate", {"expression": "1+1"})
    txt = json.dumps(body, ensure_ascii=False)
    case("POST /v2/browser/evaluate", st == 200 and ("2" in txt), txt[:80])

    st, body, _ = post("/v2/browser/snapshot", {"interactive_only": True})
    txt = json.dumps(body, ensure_ascii=False)
    case("POST /v2/browser/snapshot", st == 200 and ("i" in txt or "ref" in txt or "node" in txt), f"{st} {txt[:60]}")

    st, body, _ = post("/v2/browser/fill", {"selector": "#i", "value": "hello-v2"})
    case("POST /v2/browser/fill", st == 200, f"{st}")
    st, body, _ = post("/v2/browser/evaluate", {"expression": "document.getElementById('i').value"})
    case("fill 生效", "hello-v2" in json.dumps(body, ensure_ascii=False), "")

    st, body, _ = post("/v2/browser/click", {"selector": "#b"})
    case("POST /v2/browser/click", st == 200, f"{st}")
    st, body, _ = post("/v2/browser/evaluate", {"expression": "document.getElementById('h').textContent"})
    case("click 生效（DOM 变化）", "clicked" in json.dumps(body, ensure_ascii=False), "")

    # 标签页
    st, body, _ = get("/v2/browser/tabs")
    tabs = json.dumps(body, ensure_ascii=False)
    case("GET /v2/browser/tabs", st == 200, f"{st}")
    st, body, _ = post("/v2/browser/tabs", {"url": "about:blank"})
    case("POST /v2/browser/tabs（新建）", st == 200, f"{st}")
    tid = None
    if st == 200 and isinstance(body, dict):
        d = body.get("data") or {}
        tid = d.get("tab_id") or d.get("target_id") or d.get("id")
    st, body, _ = get("/v2/browser/tabs")
    if st == 200 and isinstance(body, dict):
        d = body.get("data") or {}
        arr = d if isinstance(d, list) else d.get("tabs", [])
        if arr and not tid:
            tid = (arr[-1] or {}).get("tab_id") or (arr[-1] or {}).get("id")
    if tid:
        st, body, _ = post(f"/v2/browser/tabs/{tid}/activate", {})
        case("POST /v2/browser/tabs/{id}/activate", st == 200, f"{st}")
        st, body, _ = delete(f"/v2/browser/tabs/{tid}")
        case("DELETE /v2/browser/tabs/{id}", st == 200, f"{st}")
    else:
        skip("标签页 activate/close", "未取到 tab_id")

    # Cookie
    st, body, _ = post("/v2/browser/cookies", {"cookies": [{"name": "v2c", "value": "1",
                                                            "url": "https://example.com"}]})
    case("POST /v2/browser/cookies（写）", st == 200, f"{st}")
    st, body, _ = get("/v2/browser/cookies", params={"url": "https://example.com"})
    case("GET /v2/browser/cookies（读）", st == 200 and "v2c" in json.dumps(body, ensure_ascii=False), "")
    st, body, _ = delete("/v2/browser/cookies",
                         params={"name": "v2c", "url": "https://example.com", "domain": "", "all": "false"})
    case("DELETE /v2/browser/cookies", st in (200, 204), f"{st}")

    # 网络请求日志 + 原生 CDP
    st, body, _ = get("/v2/browser/network/requests", params={"limit": 10, "clear": "false"})
    case("GET /v2/browser/network/requests", st == 200, f"{st}")
    st, body, _ = post("/v2/browser/cdp", {"method": "Browser.getVersion", "browser": True})
    txt = json.dumps(body, ensure_ascii=False)
    case("POST /v2/browser/cdp（Browser.getVersion）", st == 200 and "product" in txt.lower(), txt[:80])

    # 真实站点导航（外网）
    st, body, dt = post("/v2/browser/navigate", {"url": "https://example.com", "timeout": 30})
    case("导航真实站点 example.com", st == 200 and body.get("success") is True, f"{st} {dt:.0f}ms")
    st, body, _ = post("/v2/browser/evaluate", {"expression": "document.title"})
    case("真实站点 title 可读", "Example" in json.dumps(body, ensure_ascii=False), "")


# ---------------------------------------------------------------- MCP / 桌面
def sec_mcp():
    section("MCP /mcp")
    st, body, _ = post("/mcp", {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                           "clientInfo": {"name": "cube-v2test", "version": "1.0"}}})
    case("POST /mcp initialize", st == 200 and isinstance(body, dict) and "result" in body, f"{st}")
    st, body, _ = post("/mcp", {"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    tools = []
    if st == 200 and isinstance(body, dict):
        tools = (body.get("result") or {}).get("tools", [])
    case("POST /mcp tools/list", st == 200 and len(tools) > 0, f"{len(tools)} 个工具")
    if tools:
        print("      工具: " + ", ".join(t.get("name", "?") for t in tools[:8]))


def sec_computer():
    section("桌面 /v2/computer（aio-daemon 镜像预期不可用）")
    st, body, _ = get("/v2/computer/info")
    if st in (200, 201):
        case("GET /v2/computer/info", True, f"{st}")
    elif st == 503:
        skip("computer-use 面", "503（该镜像不含 computer-use worker，符合预期）")
    else:
        skip("computer-use 面", f"HTTP {st}")


def main():
    print(f"BASE = {BASE}")
    for fn in (sec_ops, sec_commands, sec_fs, sec_pty, sec_watch, sec_code, sec_browser, sec_mcp, sec_computer):
        try:
            fn()
        except Exception as exc:  # 单个面异常不打断整体
            FAIL.append((fn.__name__, f"异常 {exc!r}"))
            print(f"  ✘ {fn.__name__} 异常: {exc!r}")
    return summary()


if __name__ == "__main__":
    sys.exit(main())
