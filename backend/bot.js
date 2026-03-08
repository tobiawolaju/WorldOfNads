export function createBots(count, floorY = 0) {
  const safeCount = Math.max(0, Number.isFinite(count) ? Math.floor(count) : 0);
  const bots = {};

  for (let i = 0; i < safeCount; i += 1) {
    const id = `bot-${i + 1}`;
    const username = `bot${i + 1}`;
    const spawn = buildBotSpawn(i);

    bots[id] = {
      id,
      username,
      x: spawn.x,
      y: floorY,
      z: spawn.z,
      rotationY: 0,
      animation: 'idle',
      isBot: true
    };
  }

  return bots;
}

function buildBotSpawn(index) {
  // Spread bots around origin in rings so they never stack on one spawn point.
  const ring = Math.floor(index / 8);
  const slot = index % 8;
  const radius = 2.8 + ring * 1.1;
  const angle = (Math.PI * 2 * slot) / 8 + ring * 0.35;
  return {
    x: Math.cos(angle) * radius,
    z: Math.sin(angle) * radius
  };
}

export function updateBots({
  bots,
  chicken,
  dt,
  pickupRadius,
  moveSpeed
}) {
  let pickupBotId = '';
  const speed = Math.max(0.01, moveSpeed);
  const stepMax = speed * dt;

  for (const bot of Object.values(bots)) {
    const dx = chicken.x - bot.x;
    const dz = chicken.z - bot.z;
    const dist2D = Math.hypot(dx, dz);

    if (dist2D > 0.0001) {
      const nx = dx / dist2D;
      const nz = dz / dist2D;
      const step = Math.min(stepMax, dist2D);
      bot.x += nx * step;
      bot.z += nz * step;
      bot.rotationY = Math.atan2(nx, nz);
      bot.animation = 'running';
    } else {
      bot.animation = 'idle';
    }

    if (!chicken.isHeld) {
      const dy = chicken.y - bot.y;
      const dist3D = Math.hypot(dx, dy, dz);
      if (dist3D <= pickupRadius) {
        pickupBotId = bot.id;
        break;
      }
    }
  }

  return { pickupBotId };
}
