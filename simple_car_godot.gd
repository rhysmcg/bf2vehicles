extends VehicleBody3D

############################################################
# Steering

@export var MAX_STEER_ANGLE = 30
@export var SPEED_STEER_ANGLE = 10
@export var MAX_STEER_SPEED = 120.0
@export var MAX_STEER_INPUT = 90.0
@export var STEER_SPEED = 1.0

@onready var max_steer_angle_rad = deg_to_rad(MAX_STEER_ANGLE)
@onready var speed_steer_angle_rad = deg_to_rad(SPEED_STEER_ANGLE)
@onready var max_steer_input_rad = deg_to_rad(MAX_STEER_INPUT)
@export  var steer_curve : Curve
@export var isAutomatic : bool = true

var current_time: float = 0.0
var is_running: bool = false

var steer_target = 0.0
var steer_angle = 0.0

############################################################
# Speed and drive direction

@export var MAX_ENGINE_FORCE = 1200.0
@export var MAX_BRAKE_FORCE = 50.0
@export var engine_brake_torque : float = 750

@export var gear_ratios : Array = [ 2.66, 1.78, 1.3, 1.0, 0.8 ] 
@export var reverse_ratio : float = -2.66
@export var final_drive_ratio : float = 2.0
@export var min_engine_rpm : float = 1000.0
@export var max_engine_rpm : float = 3750.0
@export var power_curve : Curve #0,1 0.85,1 and 1,0


var current_gear = 1 # -1 reverse, 0 = neutral, 1 - 6 = gear 1 to 6.
var clutch_position : float = 1.0 # 0.0 = clutch engaged
var current_speed_mps = 0.0

@onready var last_pos = position

#var gear_timer = 0.0

@export var gear_shift_time = 0.7
@export var ChangeDown = 0.5
@export var ChangeUp = 0.85
var gear_timer := Timer.new()

var cameraIndex = 0

###################################
@export_group("Engine Sound ")
@onready var engine_audio = $RPM2 
@onready var engine_unload =$RPM1
@onready var engine_start_idle_stop = $StartIdleStop
@onready var engine_load = $Load


@export_group("Car Parts")
@export var SteeringWheel : Node3D
###################################
# Curves have been created from BF2 envelopes
@export var rpm2_volume_curve : Curve
@export var rpm2_pitch_curve : Curve
@export var rpm1_volume_curve : Curve
@export var rpm1_pitch_curve : Curve
@export var idle_pitch_curve : Curve
@export var idle_volume_curve : Curve




@export var InsideCamera : Camera3D
@export var ChaseCamera : Camera3D


func get_speed_kph():
	return current_speed_mps * 3600.0 / 1000.0

# calculate the RPM of our engine based on the current velocity of our car
func calculate_rpm() -> float:
	# if we are in neutral, no rpm
	if current_gear == 0:
		return 0.0
		
	var wheel_circumference : float = 2.0 * PI * $JEP_mec_Paratrooper_Wheel_RR.wheel_radius
	var wheel_rotation_speed : float = 60.0 * current_speed_mps / wheel_circumference
	var drive_shaft_rotation_speed : float = wheel_rotation_speed * final_drive_ratio
	if current_gear == -1:
		# we are in reverse
		return min_engine_rpm + (drive_shaft_rotation_speed * -reverse_ratio)
	elif current_gear <= gear_ratios.size():
		return min_engine_rpm + (drive_shaft_rotation_speed * gear_ratios[current_gear - 1])
	else:
		return 0.0

############################################################
# Input

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	## PLAY START ENGINE
	engine_start_idle_stop.play()
	add_child(gear_timer)
	gear_timer.wait_time = gear_shift_time
	gear_timer.one_shot = true
	gear_timer.timeout.connect(_gear_shift_finished)
	

func _process_gear_inputs(delta : float):
	
	var rpm = calculate_rpm()
	
	# Automatic Gear
	if isAutomatic:
		if rpm < (max_engine_rpm * ChangeDown) and current_gear > 1:
			current_gear = current_gear - 1
			clutch_position = 0.0
			engine_load.play()
			gear_timer.start()
			
		elif rpm > (max_engine_rpm * ChangeUp) and current_gear < gear_ratios.size() and current_gear != -1:
			current_gear = current_gear + 1
			clutch_position = 0.0
			engine_load.play()
			gear_timer.start()

			
	# Manual Gear
	else:
		if Input.is_action_just_pressed("GearDown") and current_gear > -1:
			current_gear = current_gear - 1
			clutch_position = 0.0
			engine_load.play()
			gear_timer.start()
		elif Input.is_action_just_pressed("GearUp") and current_gear < gear_ratios.size():
			current_gear = current_gear + 1
			clutch_position = 0.0
			engine_load.play()
			gear_timer.start()
		else:
			clutch_position = 1.0

func _process(delta : float):
	_process_gear_inputs(delta)
	_changeCamera()
	
	if is_running:
		current_time += delta
		print("Elapsed Time: ", snapped(current_time, 0.01))
	
func _gear_shift_finished():
	clutch_position = 1.0

func _physics_process(delta):
	# how fast are we going in meters per second?
	# current_speed_mps = (position - last_pos).length() / delta
	current_speed_mps = linear_velocity.length()
	
	# get our joystick inputs
	var steer_val = Input.get_axis("move_left", "move_right")
	var throttle_val = Input.get_action_strength("move_forward")
	var brake_val = Input.get_action_strength("move_backward")
	
	var rpm = calculate_rpm()
	var rpm_factor = clamp(rpm / max_engine_rpm, 0.0, 1.0)
	var power_factor = power_curve.sample_baked(rpm_factor)
	
	###
	### ACCELRATION
	###
	
	engine_force = 0.0
	brake = 0.0

		
	## Gear change to reverse when pretty much stopped
	if isAutomatic:
		if current_gear == 1:
			if current_speed_mps <= 1.0 and brake_val > 0.1:
				current_gear = -1
		elif current_gear == -1:
			if current_speed_mps <= 1.0 and throttle_val > 0.1:
				current_gear = 1
				
	## REVERSE 
	if current_gear == -1:
		if isAutomatic:
			engine_force = (clutch_position * brake_val * power_factor * reverse_ratio * final_drive_ratio * MAX_ENGINE_FORCE) * -1.0
		else:
			engine_force = (clutch_position * throttle_val * power_factor * reverse_ratio * final_drive_ratio * MAX_ENGINE_FORCE) * -1.0
		
	elif current_gear > 0 and current_gear <= gear_ratios.size():
		engine_force = -1 * (clutch_position * throttle_val * power_factor * gear_ratios[current_gear - 1] * final_drive_ratio * MAX_ENGINE_FORCE) 
	else:
		engine_force = 0.0
	
	
	## BRAKING
	if current_gear > 0:
		if brake_val > 0.1: 
			brake = (brake_val * MAX_BRAKE_FORCE) * 0.01
			
		if throttle_val < 0.1:
			brake += engine_brake_torque * 0.01
		
		
			
	## IN REVERSE
	elif current_gear == -1:
		
		if (isAutomatic and throttle_val > 0.1) or (!isAutomatic and brake_val > 0.1):
			if isAutomatic:
				brake = throttle_val * MAX_BRAKE_FORCE
			else:
				brake = brake_val * MAX_BRAKE_FORCE
					
	var max_steer_speed = MAX_STEER_SPEED * 1000.0 / 3600.0
	var steer_speed_factor = clamp(current_speed_mps / max_steer_speed, 0.0, 1.0)

	if (abs(steer_val) < 0.05):
		steer_val = 0.0
	elif steer_curve:
		if steer_val < 0.0:
			steer_val = -steer_curve.sample_baked(-steer_val)
		else:
			steer_val = steer_curve.sample_baked(steer_val)
	
	steer_angle = steer_val * lerp(max_steer_angle_rad, speed_steer_angle_rad, steer_speed_factor)
	steering = -steer_angle

	
	# remember where we are
	last_pos = position
	
	
	var speed = get_speed_kph()
	var is_driving_fast_enough : bool = current_speed_mps > 5.0
	

	## PLay RPM2 and MUTE RPM1
	if (throttle_val > 0.1 and current_gear > 0) or (isAutomatic and (brake_val > 0.1 and current_gear == -1) or (!isAutomatic and throttle_val > 0.1 and current_gear == -1)):
		engine_unload.volume_linear = 0.0
		engine_audio.volume_linear = rpm2_volume_curve.sample_baked(rpm_factor)
		engine_audio.pitch_scale = rpm2_pitch_curve.sample_baked(rpm_factor)

	## Engine Braking. Play RPM1 and mute RPM2
	elif is_driving_fast_enough:
		engine_audio.volume_linear = 0.0
		engine_unload.volume_linear = rpm1_volume_curve.sample_baked(rpm_factor)
		engine_unload.pitch_scale = rpm1_pitch_curve.sample_baked(rpm_factor)
	
	#Rev engine on Neutral
	elif current_gear == 0 and throttle_val > 0.1:
		engine_unload.volume_linear = 0.0
		engine_audio.volume_linear = rpm2_volume_curve.sample_baked(1.0)
		engine_audio.pitch_scale = rpm2_pitch_curve.sample_baked(1.0)
	else:
		engine_audio.volume_linear = 0.0
		engine_unload.volume_linear = 0.0
	# 
	engine_start_idle_stop.volume_linear = idle_volume_curve.sample_baked(rpm_factor)
	engine_start_idle_stop.pitch_scale = idle_pitch_curve.sample_baked(rpm_factor)
	
	# Calculated from python script
	engine_start_idle_stop.stream.loop_mode = 1
	engine_start_idle_stop.stream.loop_begin = 21809
	engine_start_idle_stop.stream.loop_end = 57696
		
	# Still need STOP to code
	
	
	var info = 'Speed: %.0f, RPM: %.0f (gear: %d), Throttle %.0f, Brake %.0f, Engine Force %.0f, Brake Force %.0f, Clutch %.0f'  % [ speed, rpm, current_gear, throttle_val, brake_val, engine_force, brake, clutch_position ]
	#print(info)
	#$Info.text = info
	
func _changeCamera():
	# 0 = inside, 1 = chase, 2 = front chase, 3 = flyby
	
	var cameras = ["Inside","Chase"]
	if Input.is_action_just_pressed("ChangeCamera"):
		cameraIndex = cameraIndex + 1
		cameraIndex = (cameraIndex % 2)
		
		if cameras[cameraIndex] == "Inside":
			InsideCamera.make_current()
		elif cameras[cameraIndex] == "Chase":
			ChaseCamera.make_current()
		
	if Input.is_action_just_pressed("StartTimer"):
		
		if !is_running:
			start_timer()
		else:
			stop_timer()
			
	if Input.is_action_just_pressed("ResetTimer"):
		reset_timer()
		
		

func start_timer() -> void:
	is_running = true
	print("Stopwatch Started!")

func stop_timer() -> void:
	is_running = false
	print("Stopwatch Stopped at: ", snapped(current_time, 0.01))

func reset_timer() -> void:
	current_time = 0.0
	print("Stopwatch Reset to 0.0!")
	
