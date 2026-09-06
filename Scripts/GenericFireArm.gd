extends Node3D

var tweakFile = "Car_Horn.tweak"
var weaponName = "Car_Horn"
var Fire1P = AudioStreamPlayer3D.new()
var Fire1P_Outdoor = AudioStreamPlayer3D.new()
var Fire3P = AudioStreamPlayer3D.new()
var BoltClick = AudioStreamPlayer3D.new()
var TriggerClick = AudioStreamPlayer3D.new()
var SwitchFireRate = AudioStreamPlayer3D.new()
var Reload1P = AudioStreamPlayer3D.new()
var Reload3P = AudioStreamPlayer3D.new()
var Deploy1P = AudioStreamPlayer3D.new()
var Deploy3P = AudioStreamPlayer3D.new()
var Zoom = AudioStreamPlayer3D.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	# Read the Tweak File and make the streams
	Fire1P.stream = load("res://" + "objects/vehicles/common/car_horn/sound/horn.wav")
	Fire1P.volume_linear = 0.6
	Fire1P.pitch_scale = 1.0
	Fire1P.name = "S_" + weaponName + "_Fire1P"
	
	add_child(Fire1P)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _input(event: InputEvent) -> void:
	
	## 1p & 3p sounds set up
	if Input.is_action_just_pressed("c_PIFire"):
		Fire1P.playing = true
		
