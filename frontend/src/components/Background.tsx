import './Background.css'

const BackgroundPattern = () => {
  const numPatterns = 100
  const patterns = Array.from({ length: numPatterns }, (_, i) => {
    const rotation = Math.floor(Math.random() * 360)
    const left = Math.random() * 100
    const top = Math.random() * 100

    return (
      <div
        key={i}
        className="pattern-tile"
        style={{
          transform: `rotate(${rotation}deg)`,
          left: `${left}vw`,
          top: `${top}vh`,
        }}
      />
    )
  })

  return <div className="pattern-background">{patterns}</div>
}

export default BackgroundPattern
