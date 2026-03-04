import { v4 as uuidv4 } from "uuid";

export default class Player {
  constructor(ws) {
    this.id = uuidv4();
    this.ws = ws;
    this.x = 0;
    this.y = 0;
    this.z = 0;
    this.rotY = 0;
    this.inputs = { forward: false, back: false, left: false, right: false };
  }

  update(dt) {
    const speed = 5; // units per second
    if (this.inputs.forward) this.z -= speed * dt;
    if (this.inputs.back) this.z += speed * dt;
    if (this.inputs.left) this.x -= speed * dt;
    if (this.inputs.right) this.x += speed * dt;
  }

  toJSON() {
    return {
      id: this.id,
      x: this.x,
      y: this.y,
      z: this.z,
      rotY: this.rotY
    };
  }
}
//player.js