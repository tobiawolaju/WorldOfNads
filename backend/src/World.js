import Player from "./Player.js";
import { MSG } from "./MessageTypes.js";

export default class World {
  constructor() {
    this.players = new Map();
  }

  addPlayer(ws) {
    const player = new Player(ws);
    this.players.set(player.id, player);
    return player;
  }

  removePlayer(id) {
    this.players.delete(id);
  }

  handleInput(id, inputs) {
    const player = this.players.get(id);
    if (player) player.inputs = inputs;
  }

  update(dt) {
    for (const player of this.players.values()) {
      player.update(dt);
    }
  }

  getState() {
    return {
      type: MSG.STATE,
      players: Array.from(this.players.values()).map(p => p.toJSON())
    };
  }
}







