import re
import os

path = r'c:\Users\tobia\Desktop\projects\WorldOfNads\godot\scripts\LobbyManager.gd'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

target_str = """\tstatus_label.text = "✅ Server awake. Loading game..."
\t
\t# Load the real gameplay scene that connects via WebSocket
\tget_tree().change_scene_to_file("res://scenes/gameplay2d.tscn")"""

# Alternatively, just use regex so we aren't crippled by line endings:
pat = re.compile(r"status_label\.text = \"✅ Server awake\. Loading game\.\.\.\"\s*# Load the real gameplay scene that connects via WebSocket\s*(?:get_tree\(\)\.change_scene_to_file|TransitionScreen\.change_scene)\(\"res://scenes/gameplay2d\.tscn\"\)")

repl = """for i in range(5, 0, -1):
\t\tstatus_label.text = "✅ Server awake. Loading in %d..." % i
\t\tawait get_tree().create_timer(1.0).timeout
\tstatus_label.text = "✅ Let's go!"
\t
\t# Load the real gameplay scene that connects via WebSocket
\tTransitionScreen.change_scene("res://scenes/gameplay2d.tscn")"""

new_text = pat.sub(repl, text)

with open(path, 'w', encoding='utf-8') as f:
    f.write(new_text)

print("done")
