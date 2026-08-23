extends VehicleBody3D

var max_rpm = 450
var max_torque = 300
var turn_speed = 3
var turn_amount = 0.3
var vehicle_inertia = 2.0

@export var RL_wheel : VehicleWheel3D
@export var RR_wheel : VehicleWheel3D

func _ready() -> void:
	greeting()

func _physics_process(delta):
	var dir = Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	var steering_dir = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var rpm_left = abs(RL_wheel.get_rpm())
	var rpm_right = abs(RR_wheel.get_rpm())
	var RPM = (rpm_left + rpm_right) / 2.0
	var torque = dir * max_torque * (1.0 - RPM / max_rpm)
	engine_force = torque
	steering = lerp(steering, steering_dir * turn_amount, turn_speed * delta)
	
	print(dir)
	
	if dir == 0:
		brake = vehicle_inertia

func greeting():
	print("hello")
	print("hello")
	print("hello")
