// Brief — single-character brief card.
// Used inside ui_kits/character_briefs/index.html.

function Brief({ heroId, role, palette, stats, silhouette, proportions, texture, vibe, accent, totem, tintClass }) {
  return (
    <div className="brief">
      <div className="brief-head">
        <div className={`totem-square ${tintClass}`}><img src={totem} alt="" /></div>
        <div>
          <div className="name">{heroId}</div>
          <div className="role">{role}</div>
        </div>
      </div>
      <div className="row"><div className="k">Palette</div>
        <div className="palette">
          {palette.map((c, i) => <span key={i} style={{ background: c }} />)}
        </div>
      </div>
      {stats && (
        <div className="row"><div className="k">Stats</div>
          <div className="stats">
            {stats.map(([v, label], i) => (
              <div className="stat" key={i}><b>{v}</b>{label}</div>
            ))}
          </div>
        </div>
      )}
      <div className="row"><div className="k">Silhouette</div><div>{silhouette}</div></div>
      <div className="row"><div className="k">Proportions</div><div>{proportions}</div></div>
      <div className="row"><div className="k">Texture</div><div>{texture}</div></div>
      <div className="vibe" style={{ color: accent }}>{vibe}</div>
    </div>
  );
}

window.Brief = Brief;
