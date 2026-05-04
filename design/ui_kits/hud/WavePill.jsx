// WavePill — top-right wave banner with backdrop blur.
// Reads from WaveDirector schedule. The eyebrow color matches the active hero's --core.

const HERO_CORE = {
  Goose: 'var(--goose-core)',
  Buffalo: 'var(--buffalo-core)',
  Fox: 'var(--fox-core)',
};

function formatTimer(seconds) {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function WavePill({ wave, hero, headline, secondsLeft }) {
  const accent = HERO_CORE[hero] || 'var(--fox-core)';
  return (
    <div className="wave-pill">
      <div>
        <div className="eyebrow" style={{ color: accent }}>
          Wave {wave} · {hero}'s turn
        </div>
        <div className="title">{headline}</div>
      </div>
      <div className="timer" style={{ color: accent }}>{formatTimer(secondsLeft)}</div>
    </div>
  );
}

window.WavePill = WavePill;
