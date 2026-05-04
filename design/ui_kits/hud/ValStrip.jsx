// ValStrip — bottom-center companion status pill.
// Val is the shared Australian Shepherd. Status is short, in-character.

function ValStrip({ status }) {
  return (
    <div className="val-strip">
      <div className="puck"><img src="../../assets/totems/val.svg" alt="" /></div>
      <div>
        <div className="name">Val</div>
        <div className="status">{status}</div>
      </div>
    </div>
  );
}

window.ValStrip = ValStrip;
