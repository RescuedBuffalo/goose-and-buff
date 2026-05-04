// BlenderPrompt — the dark prompt-template card at the bottom of index.html.
// Pure presentational; copy text from this prop.

function BlenderPrompt({ children }) {
  return (
    <div className="blender-prompt">
      <h3>Blender prompt template</h3>
      {children}
    </div>
  );
}

window.BlenderPrompt = BlenderPrompt;
