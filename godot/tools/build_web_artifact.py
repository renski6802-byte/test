#!/usr/bin/env python3
"""웹으로 내보낸 것을 파일 하나짜리 HTML 로 묶는다.

왜 이런 짓을 하냐면 — 게시할 수 있는 페이지는 바깥 파일을 못 가져온다.
그래서 wasm 도 pck 도 페이지 안에 넣어야 하는데, wasm 이 35MB 라 그대로는 한도를 넘는다.
gzip 으로 줄여 base64 로 심고, 브라우저가 DecompressionStream 으로 푼 뒤
fetch 를 가로채 로더에게 건네준다.

쓰는 법:
    godot --headless --path godot --export-release "Web" ../build/web/index.html
    python3 godot/tools/build_web_artifact.py build/web out/play.html
"""

import base64
import gzip
import sys
from pathlib import Path


def packed(path: Path) -> str:
    return base64.b64encode(gzip.compress(path.read_bytes(), 9)).decode("ascii")


def build(src: Path, dst: Path) -> None:
    engine_js = (src / "index.js").read_text(encoding="utf-8")
    # 스크립트 태그 안에 넣을 것이라 닫는 태그가 문자열에 섞여 있으면 잘린다
    engine_js = engine_js.replace("</script>", "<\\/script>")

    worklet_js = (src / "index.audio.worklet.js").read_text(encoding="utf-8")
    worklet_b64 = base64.b64encode(worklet_js.encode("utf-8")).decode("ascii")

    wasm_b64 = packed(src / "index.wasm")
    pck_b64 = packed(src / "index.pck")

    html = TEMPLATE.replace("__ENGINE_JS__", engine_js)
    html = html.replace("__WASM_B64__", wasm_b64)
    html = html.replace("__PCK_B64__", pck_b64)
    html = html.replace("__WORKLET_B64__", worklet_b64)

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(html, encoding="utf-8")
    mb = dst.stat().st_size / 1048576
    print(f"{dst}  {mb:.2f} MB")
    if mb > 15.5:
        print("  경고: 게시 한도(16MB)에 너무 가깝다")


TEMPLATE = r"""<title>대항해 프로토타입 — 브라우저에서 바로</title>

<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #0b1016; color: #d9cfb2;
         font-family: "Pretendard", -apple-system, "Apple SD Gothic Neo",
                      "Noto Sans KR", system-ui, sans-serif; }
  .wrap { max-width: 1280px; margin: 0 auto; padding: 18px 16px 40px;
          display: flex; flex-direction: column; gap: 14px; }
  h1 { font-size: 20px; margin: 0; font-weight: 700; letter-spacing: -.01em; }
  p.lede { margin: 0; color: #9a917c; font-size: 13.5px; max-width: 70ch; }
  .frame { position: relative; width: 100%; aspect-ratio: 16 / 10;
           background: #05080d; border: 1px solid #3b414d; border-radius: 3px;
           overflow: hidden; }
  canvas { display: block; width: 100%; height: 100%; outline: none; }
  .boot { position: absolute; inset: 0; display: flex; flex-direction: column;
          align-items: center; justify-content: center; gap: 12px;
          background: #05080d; text-align: center; padding: 24px; }
  .boot[hidden] { display: none; }
  .bar { width: min(420px, 70%); height: 3px; background: #262c36; border-radius: 2px; overflow: hidden; }
  .bar > i { display: block; height: 100%; width: 0%; background: #d9a441; transition: width .2s; }
  .boot small { color: #6b6353; font-size: 12px; max-width: 52ch; line-height: 1.6; }
  .keys { display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 12.5px; color: #9a917c; }
  kbd { font-family: ui-monospace, "SF Mono", Consolas, monospace; font-size: 11px;
        background: #1b1f26; border: 1px solid #434a57; border-bottom-width: 2px;
        border-radius: 3px; padding: 0 5px; color: #d9cfb2; }
  .err { color: #dc6152; font-size: 13px; max-width: 60ch; line-height: 1.6; }
</style>

<div class="wrap">
  <h1>대항해 프로토타입</h1>
  <p class="lede">
    Godot 을 설치하지 않고 브라우저에서 바로 조작합니다. 엔진과 프로젝트가 이 페이지 안에
    들어 있어서, 처음 한 번 푸는 데 몇 초 걸립니다.
  </p>

  <div class="frame">
    <canvas id="canvas" width="1440" height="900" tabindex="0"></canvas>
    <div class="boot" id="boot">
      <div id="boot-msg">엔진을 푸는 중…</div>
      <div class="bar"><i id="boot-bar"></i></div>
      <small id="boot-note">35MB 짜리 엔진을 압축해 담았습니다. 회선에 따라 20~40초 걸릴 수 있습니다.</small>
    </div>
  </div>

  <div class="keys">
    <span><kbd>←</kbd><kbd>→</kbd> 조타</span>
    <span><kbd>↑</kbd><kbd>↓</kbd> 돛</span>
    <span>화면 끌기 — 시점</span>
    <span>휠 — 줌</span>
    <span><kbd>C</kbd> 정면</span>
    <span><kbd>Q</kbd> 묻기</span>
    <span><kbd>M</kbd> 해도</span>
    <span><kbd>Space</kbd> 측량</span>
    <span><kbd>E</kbd> 입항</span>
  </div>
</div>

<script id="godot-engine">
__ENGINE_JS__
</script>

<script>
// 자료가 먼저 와야 한다. 아래에 두면 아래 로직이 읽는 시점에 아직 초기화 전이라 죽는다.
const WASM_B64 = "__WASM_B64__";
const PCK_B64 = "__PCK_B64__";
const WORKLET_B64 = "__WORKLET_B64__";

(async () => {
  "use strict";

  const boot = document.getElementById("boot");
  const msg = document.getElementById("boot-msg");
  const bar = document.getElementById("boot-bar");
  const note = document.getElementById("boot-note");
  const canvas = document.getElementById("canvas");

  const realFetch = window.fetch.bind(window);
  const step = (t, pct) => { msg.textContent = t; bar.style.width = pct + "%"; };

  function fail(text) {
    boot.hidden = false;
    msg.textContent = "실행할 수 없습니다";
    bar.parentElement.style.display = "none";
    note.className = "err";
    note.textContent = text;
  }

  if (typeof DecompressionStream === "undefined") {
    fail("이 브라우저는 DecompressionStream 을 지원하지 않습니다. 최신 크롬·엣지·사파리에서 열어 주십시오.");
    return;
  }

  // base64 → 바이트. data: URL 로 fetch 하는 편이 빠르지만 게시 환경이 그걸 막는다.
  function bytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  async function unpack(b64) {
    const raw = bytes(b64);
    const s = new Blob([raw]).stream().pipeThrough(new DecompressionStream("gzip"));
    return new Uint8Array(await new Response(s).arrayBuffer());
  }
  const breathe = () => new Promise((r) => setTimeout(r, 16));

  let wasm, pck;
  try {
    step("엔진을 푸는 중…", 15);
    await breathe();
    wasm = await unpack(WASM_B64);
    step("프로젝트를 푸는 중…", 60);
    await breathe();
    pck = await unpack(PCK_B64);
  } catch (e) {
    fail("자료를 푸는 단계에서 막혔습니다 — " + (e && e.message ? e.message : e));
    return;
  }

  // 로더는 파일을 URL 로 집으러 간다. 바깥으로 못 나가므로 여기서 가로챈다.
  const served = new Map([
    ["index.wasm", { body: wasm, type: "application/wasm" }],
    ["index.pck", { body: pck, type: "application/octet-stream" }],
  ]);
  window.fetch = function (input, init) {
    const url = typeof input === "string" ? input : (input && input.url) || "";
    for (const [name, item] of served) {
      if (url.endsWith(name)) {
        return Promise.resolve(new Response(item.body, {
          status: 200,
          headers: { "Content-Type": item.type, "Content-Length": String(item.body.length) },
        }));
      }
    }
    return realFetch(input, init);
  };

  // 오디오 워클릿만은 진짜 URL 을 요구한다. 블롭으로 만들어 끼워 넣는다.
  // 소리는 없어도 게임은 돈다. 블롭 URL 이 막히면 조용히 넘어간다.
  let workletUrl = null;
  try {
    const src = new TextDecoder().decode(bytes(WORKLET_B64));
    workletUrl = URL.createObjectURL(new Blob([src], { type: "text/javascript" }));
  } catch (e) {
    console.warn("오디오 워클릿을 준비하지 못했습니다:", e);
  }
  if (workletUrl && window.AudioWorklet && AudioWorklet.prototype.addModule) {
    const addModule = AudioWorklet.prototype.addModule;
    AudioWorklet.prototype.addModule = function (url) {
      return addModule.call(this, String(url).endsWith(".worklet.js") ? workletUrl : url);
    };
  }

  // 페이지를 스크롤하려다 캔버스 위에 있으면 카메라가 확 당겨진다. 캔버스 안에서만 먹게 한다.
  canvas.addEventListener("wheel", (e) => e.preventDefault(), { passive: false });

  step("엔진을 켜는 중…", 80);
  try {
    const engine = new Engine({
      canvas: canvas,
      executable: "index",
      mainPack: "index.pck",
      // 0 = 캔버스 크기를 건드리지 않는다. 데스크톱과 같은 1440x900 으로 그리고
      // 화면에 맞추는 일은 CSS 가 한다. 브라우저가 크기를 바꾸면 배치가 어긋난다.
      canvasResizePolicy: 0,
      focusCanvas: true,
      args: [],
      ensureCrossOriginIsolationHeaders: false,
    });
    await engine.startGame({
      onProgress: (cur, total) => {
        if (total > 0) step("불러오는 중…", 80 + (cur / total) * 20);
      },
    });
    boot.hidden = true;
    canvas.focus();
  } catch (e) {
    const detail = e && e.message ? e.message : String(e);
    fail("엔진을 켜는 단계에서 막혔습니다 — " + detail +
      (/wasm|WebAssembly|CSP|unsafe/i.test(detail)
        ? "  게시 환경이 WebAssembly 실행을 막고 있습니다. 데스크톱 빌드로 드리겠습니다."
        : ""));
  }
})();
</script>
"""


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        raise SystemExit(1)
    build(Path(sys.argv[1]), Path(sys.argv[2]))
