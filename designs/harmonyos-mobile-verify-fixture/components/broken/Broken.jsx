/* BROKEN on purpose — this file violates several rules at once. */
import { useState } from "react";   /* R4: the compiler strips react imports */

export function Broken({ label }) {
  const [on, setOn] = useState(false);
  /* R7: data-hm-light belongs on interactive elements, not a plain div. */
  return (
    <div className="hm-broken" data-hm-light="" onClick={() => setOn(!on)}>
      <span>{label}</span>
      {/* BROKEN: data-hm-light with nothing interactive about it (R7). */}
      <div className="hm-broken-static" data-hm-light="">pure content</div>
    </div>
  );
}
/* R3/R8: no sibling .d.ts and no sibling .prompt.md */
