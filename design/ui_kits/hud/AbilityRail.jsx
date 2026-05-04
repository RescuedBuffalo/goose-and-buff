// AbilityRail — Q/E/F/R abilities, bottom-left.
// Each slot: keybind chip + glyph (Lucide-styled inline SVG) or cooldown number.

function AbilitySlot({ keybind, glyph, cooldown }) {
  const cd = typeof cooldown === 'number' && cooldown > 0;
  return (
    <div className={`ability ${cd ? 'cd' : ''}`}>
      <div className="key">{keybind}</div>
      {cd ? <span className="cd-num">{cooldown}</span> : glyph}
    </div>
  );
}

function AbilityRail({ slots }) {
  // slots: [{ keybind: 'Q', glyph: <svg/>, cooldown: 0 }, ...]
  return (
    <div className="abilities">
      {slots.map((s, i) => (
        <AbilitySlot key={i} {...s} />
      ))}
    </div>
  );
}

window.AbilitySlot = AbilitySlot;
window.AbilityRail = AbilityRail;
