class_name PaxGame
extends RefCounted
var node: MeshInstance3D
var mat: ShaderMaterial
var cam: Camera3D
var speed := 3
func body(_n: String) -> Dictionary: return {"node": node, "material": mat}
func home_body() -> String: return "Земля"
func focused_body() -> String: return "Земля"
func camera() -> Camera3D: return cam
func set_speed(s: int) -> void: speed = s
