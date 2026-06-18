// js-driver/test/regions/fixtures/fake-guest.js
// A tiny conforming guest: records calls, echoes a prop change as an event.
export default function fakeGuest(canvas, props, ctx) {
  const calls = { props: [], resize: [], frames: 0, destroyed: false };
  // Echo the initial props count back as a "ready-count" event.
  if (props) ctx.emit({ kind: "init", count: props.count ?? 0 });
  return {
    onProps(p) { calls.props.push(p); ctx.emit({ kind: "prop", count: p.count ?? 0 }); },
    onResize(w, h, dpr) { calls.resize.push([w, h, dpr]); },
    frame(_dt) { calls.frames++; },
    destroy() { calls.destroyed = true; },
    _calls: calls, // test introspection only
  };
}
