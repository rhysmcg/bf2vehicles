extends VehicleBody3D



### KEY PROBLEMS
### Slope friction is too good, can scale 30 degrees where as BF2 seems to fail just past 25 degrees
### When the car rolls back, the back wheels need to stay still and the front wheels should roll
### The car gears up when rolling backwards, interpreting it as forward motion
### I should be smoothly able to reverse J turn and back into first gear. It needs a certain speed to do this
### Somethign needs to improve with the brakes
### RPM 2

############################################################
# Steering

@export var MAX_STEER_ANGLE = 30
@export var SPEED_STEER_ANGLE = 10
@export var MAX_STEER_SPEED = 120.0
@export var MAX_STEER_INPUT = 90.0
@export var STEER_SPEED = 1.0


@export var max_steep_angle_deg: float = 25.0  # Angle considered "fully steep"
@export var flat_friction: float = 30.0
@export var steep_friction: float = 0.6

@onready var max_steer_angle_rad = deg_to_rad(MAX_STEER_ANGLE)
@onready var speed_steer_angle_rad = deg_to_rad(SPEED_STEER_ANGLE)
@onready var max_steer_input_rad = deg_to_rad(MAX_STEER_INPUT)
@export  var steer_curve : Curve
@export var isAutomatic : bool = true
@export var useClutchedTorque : bool = true
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

@export var gear_shift_time = 0.25 ## 0.7 WHAT A SCAME?!?
@export var ChangeDown = 0.5
@export var ChangeUp = 0.85
var gear_timer := Timer.new()

###################################
@export_group("Engine Sound ")
@onready var engine_audio = $RPM2 
@onready var engine_audio_pitch = engine_audio.pitch_scale
@onready var engine_audio_volume = engine_audio.volume_linear

@onready var engine_unload =$RPM1
@onready var engine_unload_pitch = engine_unload.pitch_scale
@onready var engine_unload_volume = engine_unload.volume_linear

@onready var engine_start_idle_stop = $StartIdleStop
@onready var engine_start_idle_stop_pitch = engine_start_idle_stop.pitch_scale
@onready var engine_start_idle_stop_volume = engine_start_idle_stop.volume_linear

@onready var engine_load = $Load
@onready var engine_load_pitch = engine_load.pitch_scale
@onready var engine_load_pitch_volume = engine_load.volume_linear
var current_rpm: float = 1000.0
var load_blend: float = 0.0
var shift_start_rpm: float = 1000.0

@export_group("Car Parts")
@export var SteeringWheel : Node3D
@export var wheels: Array[VehicleWheel3D]
@export var steeringWheel_min_rotation = -60
@export var steeringWheel_max_rotation = 60
@export var steering_speed = 300
###################################
@export_group("Engine Audio Curves")
# Curves have been created from BF2 envelopes
@export var rpm2_volume_curve : Curve
@export var rpm2_pitch_curve : Curve
@export var rpm1_volume_curve : Curve
@export var rpm1_pitch_curve : Curve
@export var idle_pitch_curve : Curve
@export var idle_volume_curve : Curve


@export_group("Camera Settings")

@export var VehicleCamera : Camera3D
@export var CameraMount : Node3D
@export var chaseDistance = 15
@export var chaseAngle = 0.15
@export var chaseOffset = Vector3(0,1,7)
@export var CameraPosition = Vector3(0,0.1,0)
@export var cameras = ["Inside","Chase", "FrontChase", "Flyby"]
var cameraIndex = 0
var ChaseCameraSpring := SpringArm3D.new()
var CameraInsideRotation = Vector3(0,0,0)

@export var mouse_sensitivity: float = 0.003

# Accumulators to manage total camera rotation angles smoothly
var rotation_x: float = 0.0
var rotation_y: float = 0.0

# Define boundaries to clamp looking up/down and left/right inside the interior
@export var min_pitch_deg: float = -20.0   # Looking down limit
@export var max_pitch_deg: float = 20.0    # Looking up limit
@export var min_yaw_deg: float = -120.0    # Looking left limit
@export var max_yaw_deg: float = 120.0     # Looking right limit


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
	
	
	# Pair Camera
	CameraMount.add_child(ChaseCameraSpring)
	chaseOffset.z = chaseOffset.z * -1
	ChaseCameraSpring.position = chaseOffset
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process_gear_inputs(delta : float):
	
	var rpm = calculate_rpm()
# Automatic Gear
	if isAutomatic:
		if rpm < (max_engine_rpm * ChangeDown) and current_gear > 1:
			current_gear = current_gear - 1
			clutch_position = 0.0
			shift_start_rpm = current_rpm # Capture RPM at start of shift
			engine_load.play()
			#gear_timer.start()
			clutch_position = 1.0
			
		elif rpm > (max_engine_rpm * ChangeUp) and current_gear < gear_ratios.size() and current_gear != -1:
			current_gear = current_gear + 1
			clutch_position = 0.0
			shift_start_rpm = current_rpm # Capture RPM at start of shift
			engine_load.play()
			gear_timer.start()

	# Manual Gear
	else:
		if Input.is_action_just_pressed("GearDown") and current_gear > -1:
			current_gear = current_gear - 1
			clutch_position = 0.0
			shift_start_rpm = current_rpm
			engine_load.play()
			#gear_timer.start()
			clutch_position = 1.0
		elif Input.is_action_just_pressed("GearUp") and current_gear < gear_ratios.size():
			current_gear = current_gear + 1
			clutch_position = 0.0
			shift_start_rpm = current_rpm
			engine_load.play()
			gear_timer.start()

func _process(delta : float):
	_process_gear_inputs(delta)
	_changeCamera()
	adjust_wheel_friction()
	
	
	## This allows "Flyby" to work
	if cameras[cameraIndex] == "Flyby":
		VehicleCamera.look_at(global_position, Vector3.UP)
	
	if is_running:
		current_time += delta
		print("Elapsed Time: ", snapped(current_time, 0.01))
	
func _gear_shift_finished():
	clutch_position = 1.0

func adjust_wheel_friction():
	var global_up: Vector3 = Vector3.UP
	var vehicle_up: Vector3 = global_transform.basis.y
	var angle_rad: float = vehicle_up.angle_to(global_up)
	var angle_deg: float = rad_to_deg(angle_rad)
	var interpolation_factor: float = clamp(angle_deg / max_steep_angle_deg, 0.0, 1.0)
	var current_friction: float = lerp(flat_friction, steep_friction, interpolation_factor)
	for wheel in wheels:
		if wheel is VehicleWheel3D:
			wheel.wheel_friction_slip = current_friction

func _physics_process(delta):
	# how fast are we going in meters per second?
	# current_speed_mps = (position - last_pos).length() / delta
	current_speed_mps = linear_velocity.length()
	
	# get our joystick inputs
	var steer_val = Input.get_axis("move_left", "move_right")
	var throttle_val = Input.get_action_strength("move_forward")
	var brake_val = Input.get_action_strength("move_backward")
	
	var target_wheel_rpm = calculate_rpm()
	
	if clutch_position < 1.0:
		# Calculate the required RPM drop speed so it takes the full gear_shift_time (0.7s)
		var rpm_difference = abs(shift_start_rpm - target_wheel_rpm)
		var drop_rate = rpm_difference / gear_shift_time
		
		# Linearly move current_rpm toward target_wheel_rpm over 0.7 seconds
		current_rpm = move_toward(current_rpm, target_wheel_rpm, drop_rate * delta)
	else:
		# Clutch engaged: lock RPM directly to wheel speed
		current_rpm = lerp(current_rpm, target_wheel_rpm, 25.0 * delta)

	var rpm_factor = clamp(current_rpm / max_engine_rpm, 0.0, 1.0)
	var power_factor = power_curve.sample_baked(rpm_factor)

	###
	### ACCELRATION
	###
	
	engine_force = 0.0
	brake = 0.0

		
	## Gear change to reverse when pretty much stopped
	if isAutomatic:
		if current_gear == 1:
			if current_speed_mps <= 6.0 and brake_val > 0.1:
				current_gear = -1
		elif current_gear == -1:
			if current_speed_mps <= 6.0 and throttle_val > 0.1:
				current_gear = 1
				
	## REVERSE 
	if current_gear == -1:
		if isAutomatic:
			engine_force = (clutch_position * brake_val * power_factor * reverse_ratio * final_drive_ratio * MAX_ENGINE_FORCE) * -1.0
		else:
			# Manual mode uses throttle_val to accelerate backwards
			engine_force = (clutch_position * throttle_val * power_factor * reverse_ratio * final_drive_ratio * MAX_ENGINE_FORCE) * -1.0
		
	elif current_gear > 0 and current_gear <= gear_ratios.size():
		#ALWAYS KEEP CLUTCH IN
		#clutch_position = 1.0
		
		# The clutch just affects the sound, but doesn't affect the torque/drive of the car
		if not useClutchedTorque:
			clutch_position = 1.0
			engine_force = -1 * (throttle_val * power_factor * gear_ratios[current_gear - 1] * final_drive_ratio * MAX_ENGINE_FORCE) 
		
		# If using clutched torque, it will actually affect the drive of the car.
		else:
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
		if isAutomatic:
			# Automatic reverse: Forward throttle acts as the brake
			if throttle_val > 0.1:
				brake = (throttle_val * MAX_BRAKE_FORCE) * 0.01
			else:
				brake = 0.0
		else:
			# Manual reverse: Brake input acts as the brake, freeing up throttle
			if brake_val > 0.1:
				brake = (brake_val * MAX_BRAKE_FORCE) * 0.01
			else:
				brake = 0.0
					
	
	## STEERING
	
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
	
	
	
	
	## STEERING WHEEL


	var steering_target = -steer_val * steeringWheel_max_rotation

	SteeringWheel.rotation_degrees.z = move_toward(
		SteeringWheel.rotation_degrees.z,
		steering_target,
		steering_speed * delta
	)
	

	# remember where we are
	last_pos = position
	
	
	var speed = get_speed_kph()
	var is_driving_fast_enough : bool = current_speed_mps > 5.0
	
	'''
	## PLay RPM2 and MUTE RPM1
	if clutch_position > 0.1: 
		if (throttle_val > 0.1 and current_gear > 0) or (isAutomatic and (brake_val > 0.1 and current_gear == -1) or (!isAutomatic and throttle_val > 0.1 and current_gear == -1)):
			engine_unload.volume_linear = 0.0
			engine_audio.volume_linear = rpm2_volume_curve.sample_baked(rpm_factor) * engine_audio_volume
			engine_audio.pitch_scale = rpm2_pitch_curve.sample_baked(rpm_factor) * engine_audio_pitch
		else:
			engine_unload.volume_linear = 1.0
			engine_audio.volume_linear = 0.0
			engine_unload.volume_linear = rpm1_volume_curve.sample_baked(rpm_factor) * engine_unload_volume
			engine_unload.pitch_scale = rpm1_pitch_curve.sample_baked(rpm_factor) * engine_unload_pitch
	else:
		engine_unload.volume_linear = 1.0
		engine_audio.volume_linear = 0.0
		engine_unload.volume_linear = rpm1_volume_curve.sample_baked(rpm_factor) * engine_unload_volume
		engine_unload.pitch_scale = rpm1_pitch_curve.sample_baked(rpm_factor)  * engine_unload_pitch
	# 
	engine_start_idle_stop.volume_linear = idle_volume_curve.sample_baked(rpm_factor) * engine_start_idle_stop_volume
	engine_start_idle_stop.pitch_scale = idle_pitch_curve.sample_baked(rpm_factor) * engine_start_idle_stop_pitch
	'''
	
## AUDIO BLENDING
	# Determine if the engine is actively driving the wheels
	var is_under_load = false
	if (throttle_val > 0.1 and current_gear > 0) or \
	   (isAutomatic and brake_val > 0.1 and current_gear == -1) or \
	   (!isAutomatic and throttle_val > 0.1 and current_gear == -1):
		is_under_load = true
		
	# Target 1.0 (RPM2) if accelerating AND clutch is engaged. Otherwise 0.0 (RPM1).
	var target_load = 1.0 if (is_under_load and clutch_position > 0.5) else 0.0
	
	# Smoothly crossfade between load and unload sounds
	load_blend = lerp(load_blend, target_load, 15.0 * delta)

	# RPM2 (Load)
	engine_audio.volume_linear = rpm2_volume_curve.sample_baked(rpm_factor) * engine_audio_volume * load_blend
	engine_audio.pitch_scale = rpm2_pitch_curve.sample_baked(rpm_factor) * engine_audio_pitch

	# RPM1 (Unload / Engine Braking / Shifting)
	engine_unload.volume_linear = rpm1_volume_curve.sample_baked(rpm_factor) * engine_unload_volume * (1.0 - load_blend)
	engine_unload.pitch_scale = rpm1_pitch_curve.sample_baked(rpm_factor) * engine_unload_pitch

	# Idle Sound
	engine_start_idle_stop.volume_linear = idle_volume_curve.sample_baked(rpm_factor) * engine_start_idle_stop_volume
	engine_start_idle_stop.pitch_scale = idle_pitch_curve.sample_baked(rpm_factor) * engine_start_idle_stop_pitch
	
	# Calculated from python script
	engine_start_idle_stop.stream.loop_mode = 1
	engine_start_idle_stop.stream.loop_begin = 21809
	engine_start_idle_stop.stream.loop_end = 57696
	
		
	# Still need STOP to code
	
	
	var info = 'Speed: %.0f, RPM: %.0f (gear: %d), Throttle %.0f, Brake %.0f, Engine Force %.0f, Brake Force %.0f, Clutch %.0f, steering %0.f'  % [ speed, target_wheel_rpm, current_gear, throttle_val, brake_val, engine_force, brake, clutch_position, steer_angle]
	print(info)
	#$Info.text = info

## DELETE THE extra cameras. Just move the camera quickly!
func _changeCamera():

	## NOT Sure how to use this 15 number
	
	
	if Input.is_action_just_pressed("ChangeCamera"):
		cameraIndex = cameraIndex + 1
		cameraIndex = (cameraIndex % 4)
		
		if cameras[cameraIndex] == "Inside":
			ChaseCameraSpring.rotation_degrees = Vector3(0,0,0)
			
			VehicleCamera.reparent(CameraMount, false)
			VehicleCamera.position = CameraPosition
			VehicleCamera.rotation_degrees = CameraInsideRotation #problem here. It's doing local rotation? 
			
		# chaseDistance = 15. Perhaps i need to subtract this number?? More testing needed later
		# I'm also not happy at the X offset of the chase and especially front chase camera. Need to compare with BF Editor
		# Perhaps it moves the Camera Mount to 0,0,0 except during inside?
		elif cameras[cameraIndex] == "Chase":
			
			## MAKE this parent to the Vehicle itself OR make the ChaseCameraSpring attach to the vehicle itself
			VehicleCamera.reparent(ChaseCameraSpring, false)
			ChaseCameraSpring.reparent(self)
			ChaseCameraSpring.position = Vector3.ZERO
			VehicleCamera.position = Vector3.ZERO
			VehicleCamera.rotation_degrees = Vector3.ZERO
			
			ChaseCameraSpring.position = chaseOffset
			ChaseCameraSpring.spring_length = chaseDistance
			ChaseCameraSpring.rotation_degrees.x = rad_to_deg(chaseAngle) * -1
			
			
			
			
		elif cameras[cameraIndex] == "FrontChase":
			VehicleCamera.reparent(ChaseCameraSpring, false)
			ChaseCameraSpring.reparent(self)
			ChaseCameraSpring.position = Vector3.ZERO
			VehicleCamera.position = Vector3.ZERO
			VehicleCamera.rotation_degrees = Vector3.ZERO
			
			ChaseCameraSpring.position = chaseOffset
			ChaseCameraSpring.spring_length = chaseDistance
			ChaseCameraSpring.rotation_degrees.x = rad_to_deg(chaseAngle) * -1
			ChaseCameraSpring.rotation_degrees.y = 180
		
		elif cameras[cameraIndex] == "Flyby":
			VehicleCamera.rotation_degrees = Vector3.ZERO
			var distance_ahead = 15.0
			var side_offset = 0.0
			var height_offset = 1.2

			var forward_dir = -global_transform.basis.z.normalized()
			var right_dir = global_transform.basis.x.normalized()
			
			## Do some collision detection. If not inside a static object or terrain. If it is, pick another location? or drop it somewhere on the terrain somewhere
			var flyby_pos = global_position + (forward_dir * distance_ahead) + (right_dir * side_offset)
			flyby_pos.y += height_offset
			
			VehicleCamera.reparent(get_tree().current_scene)
			VehicleCamera.global_position = flyby_pos
			
		
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

func _unhandled_input(event: InputEvent) -> void:
	
	## Move camera with the mouse
	if cameras[cameraIndex] == "Inside":
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotation_y -= event.relative.x * mouse_sensitivity
			rotation_x -= event.relative.y * mouse_sensitivity
			var min_pitch_rad = deg_to_rad(min_pitch_deg)
			var max_pitch_rad = deg_to_rad(max_pitch_deg)
			var min_yaw_rad = deg_to_rad(min_yaw_deg)
			var max_yaw_rad = deg_to_rad(max_yaw_deg)
			rotation_x = clampf(rotation_x, min_pitch_rad, max_pitch_rad)
			rotation_y = clampf(rotation_y, min_yaw_rad, max_yaw_rad)
			VehicleCamera.rotation.x = rotation_x
			VehicleCamera.rotation.y = rotation_y
			VehicleCamera.rotation.z = 0.0
			CameraInsideRotation = VehicleCamera.rotation_degrees
			
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
