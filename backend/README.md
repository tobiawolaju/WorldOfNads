# WorldOfNads Backend

This document outlines the file structure and purpose of each file in the backend of the WorldOfNads project.

## File Structure

```
backend/
├───package-lock.json
├───package.json
├───server.js
├───node_modules/
└───src/
    ├───MessageTypes.js
    ├───Player.js
    └───World.js
```

## File Descriptions

### `server.js`
This is the main entry point for the backend server. It initializes the WebSocket server using the `ws` library, handles incoming player connections, processes player inputs, and broadcasts the authoritative game state to all clients at a fixed tick rate. It contains the primary game loop and server-side physics calculations.

### `package.json`
Defines the project's metadata, including its name, version, and dependencies. Key dependencies include `ws` for the WebSocket server and `uuid` for generating unique player identifiers. It also contains scripts for running the server.

### `package-lock.json`
An auto-generated file that locks the specific versions of the project's dependencies to ensure consistent installations across different environments.

### `src/`
This directory contains the core application logic, separated into distinct modules.

#### `src/World.js`
Defines the `World` class, which is responsible for managing the overall game state. This includes maintaining a collection of all connected players and providing methods to add, remove, and update them.

#### `src/Player.js`
Defines the `Player` class. Each instance represents a player connected to the server. It holds player-specific state such as their unique ID, position (`x`, `y`, `z`), rotation, and current inputs.

#### `src/MessageTypes.js`
A utility file that exports constants for the different types of messages sent over the WebSocket connection (e.g., `CONNECT`, `STATE`, `INPUT`). This provides a clear and consistent communication protocol between the client and server.



