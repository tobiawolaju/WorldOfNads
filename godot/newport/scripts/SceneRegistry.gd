extends Node

const PLAYER_SCENE: PackedScene = preload("res://newport/scenes/Player.tscn")
const GAMEPLAY_SCENE: PackedScene = preload("res://newport/scenes/gameplay.tscn")
const LOBBY_SCENE: PackedScene = preload("res://newport/scenes/lobby.tscn")
const HOME_SCENE: PackedScene = preload("res://newport/scenes/home.tscn")
const HUD_SCENE: PackedScene = preload("res://newport/scenes/hud.tscn")
const GAMEOVER_SCENE: PackedScene = preload("res://newport/scenes/gameover.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://newport/scenes/settings.tscn")

const COMPONENT_SCENES := {
	"player2": preload("res://scenes/components/Player2.tscn"),
	"player_prop": preload("res://scenes/components/PlayerProp.tscn"),
	"npc_player": preload("res://scenes/components/NPCPlayer.tscn"),
	"bus": preload("res://scenes/components/bus.tscn"),
}
