// HeroBadge — totem puck + name + HP bar. Top-left HUD stack.
// Pure cosmetic recreation; real HP comes from Heroes.lua + Humanoid.

const HEROES = {
  Goose:   { totem: '../../assets/totems/goose.svg',   tintFloor: 'var(--goose-floor)',   maxHp: 100 },
  Buffalo: { totem: '../../assets/totems/buffalo.png', tintFloor: 'var(--buffalo-floor)', maxHp: 160 },
  Fox:     { totem: '../../assets/totems/fox.svg',     tintFloor: 'var(--fox-floor)',     maxHp: 85  },
};

function hpColor(pct) {
  if (pct >= 0.6) return 'var(--hp-full)';
  if (pct >= 0.25) return 'var(--hp-warn)';
  return 'var(--hp-crit)';
}

function HeroBadge({ heroId, hp }) {
  const h = HEROES[heroId];
  if (!h) return null;
  const pct = Math.max(0, Math.min(1, hp / h.maxHp));
  return (
    <div className={`badge ${heroId.toLowerCase()}`}>
      <div className="totem-puck" style={{ background: h.tintFloor }}>
        <img src={h.totem} alt="" />
      </div>
      <div className="col">
        <div className="name">{heroId}</div>
        <div className="hp-row">
          <div className="hp-track">
            <div className="hp-fill" style={{ width: `${pct * 100}%`, background: hpColor(pct) }} />
          </div>
          <div className="hp-num">{hp} / {h.maxHp}</div>
        </div>
      </div>
    </div>
  );
}

window.HeroBadge = HeroBadge;
