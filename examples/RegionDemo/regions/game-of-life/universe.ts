// Conway's Game of Life, authored in AssemblyScript and compiled to a freestanding
// wasm module (`asc … --runtime stub`). This is the EXTERNAL guest the Swiflow
// Regions demo hosts: DOM-free pure compute that runs inside the region's Web
// Worker. The host reads `cells()` — a pointer to bit-packed cells in linear
// memory — and blits them onto the OffscreenCanvas; see ./adapter.js.
//
// Regenerate the wasm after editing this file:  npm --prefix js-driver run build:gol

let W: i32 = 0;
let H: i32 = 0;
let nbytes: i32 = 0;
let cur: usize = 0; // front buffer: bit-packed current generation
let nxt: usize = 0; // back buffer: scratch the next generation is written into

// @inline keeps the hot neighbour scan call-free. Bit math stays in the i32
// domain (AS truncates u8 shift-amounts otherwise); only the store narrows to u8.
@inline function bget(p: usize, i: i32): i32 {
  let byte = <i32>load<u8>(p + <usize>(i >> 3));
  return (byte >> (i & 7)) & 1;
}

@inline function bset(p: usize, i: i32, on: bool): void {
  let addr = p + <usize>(i >> 3);
  let mask: i32 = 1 << (i & 7);
  let b = <i32>load<u8>(addr);
  store<u8>(addr, <u8>(on ? (b | mask) : (b & ~mask)));
}

function alloc(w: i32, h: i32): void {
  W = w;
  H = h;
  nbytes = (w * h + 7) >> 3;
  cur = heap.alloc(<usize>nbytes);
  nxt = heap.alloc(<usize>nbytes);
  memory.fill(cur, 0, <usize>nbytes);
  memory.fill(nxt, 0, <usize>nbytes);
}

export function width(): i32 { return W; }
export function height(): i32 { return H; }
export function cells(): usize { return cur; }

// Seed a lively, fully deterministic board (the classic rustwasm seed pattern).
export function init(w: i32, h: i32): void {
  alloc(w, h);
  let n = w * h;
  for (let i = 0; i < n; i++) {
    if (i % 2 == 0 || i % 7 == 0) bset(cur, i, true);
  }
}

// Blank board for tests / custom seeding via set().
export function initEmpty(w: i32, h: i32): void { alloc(w, h); }

export function set(x: i32, y: i32): void { bset(cur, y * W + x, true); }
export function get(x: i32, y: i32): i32 { return bget(cur, y * W + x); }

export function tick(): void {
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      let live = 0;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          let nx = (x + dx + W) % W; // toroidal wrap
          let ny = (y + dy + H) % H;
          live += bget(cur, ny * W + nx);
        }
      }
      let i = y * W + x;
      let alive = bget(cur, i);
      let next = (alive == 1 && (live == 2 || live == 3)) || (alive == 0 && live == 3);
      bset(nxt, i, next);
    }
  }
  let t = cur; cur = nxt; nxt = t;
}
