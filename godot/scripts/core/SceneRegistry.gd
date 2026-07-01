extends Node


const GAMEPLAY_SCENE: PackedScene = preload("res://scenes/gameplay.tscn")
const LOBBY_SCENE: PackedScene = preload("res://scenes/lobby.tscn")
const HOME_SCENE: PackedScene = preload("res://scenes/home.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const GAMEOVER_SCENE: PackedScene = preload("res://scenes/gameover.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/settings.tscn")
const MAP_SALMOGRAD_SCENE: PackedScene = preload("res://scenes/maps/salmograd.tscn")
const PROP_BUS_SCENE: PackedScene = preload("res://scenes/props/enviroment/bus.tscn")
const PROP_WAYPOINT_SCENE: PackedScene = preload("res://scenes/waypoint.tscn")

const COMPONENT_SCENES := {
	"bus": preload("res://scenes/props/enviroment/bus.tscn"),
}
