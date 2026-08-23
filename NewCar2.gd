extends VehicleBody3D

# =====================================================
# SOURCE: JEP_Paratrooper.tweak (BF2 ObjectTemplate values in comments)
# =====================================================

# =====================================================
# CHASSIS
# =====================================================

@export_group("Chassis")

# ObjectTemplate.mass 1000
@export var chassis_mass : float = 1000.0

# FIX for constant left/right lean: Godot auto-computes center_of_mass from
# the collision shape. A hand-parsed BF2 collisionmesh is rarely perfectly
# symmetric, so the auto CoM can end up off to one side, which then makes
# gravity + suspension reaction torque pull the car that way permanently.
# Overriding it to a known-good local point removes that source of lean.
# Set this to your actual visual center if Vector3.ZERO isn't right for
# your mesh's pivot.
@export var override_center_of_mass : bool = true
@export var center_of_mass_override : Vector3 = Vector3.ZERO

# Prints wheel local X positions and computed CoM at startup so you can
# quickly confirm whether the lean is a wheel-transform asymmetry (issue
# would show up as front_left.x != -front_right.x) rather than a CoM issue.
@export var print_symmetry_check : bool = true

# ObjectTemplate.gravityModifier 1.5
# VehicleBody3D already inherits gravity_scale from RigidBody3D -
# no need for a manual per-frame apply_central_force like earlier attempts.
@export var gravity_modifier : float = 1.5

# ObjectTemplate.drag 1 -> mapped to RigidBody3D linear/angular damp.
# Kept low; most of the road-speed deceleration in the telemetry comes from
# engine braking + wheel friction, not aerodynamic drag.
@export var linear_damp_value : float = 0.05
@export var angular_damp_value : float = 0.5

# Flip this if the mesh's forward axis doesn't match Godot's -Z forward
# (BF2 uses +Z forward, Godot uses -Z forward).
@export var mesh_rotated_fix : bool = false

# =====================================================
# ENGINE  (ObjectTemplate.newCar2.* / setTorque / setDifferential / setGear*)
# =====================================================

@export_group("BF2 Engine")

# ObjectTemplate.setTorque 300
@export var torque : float = 300.0

# ObjectTemplate.setDifferential 2
@export var differential : float = 2.0

# ObjectTemplate.setGearRatios 2.66 1.78 1.3 1 0.8
@export var gear_ratios : Array[float] = [2.66, 1.78, 1.3, 1.0, 0.8]

# ObjectTemplate.setGearUp / setGearDown  (fraction of max_rpm)
@export var gear_up : float = 0.85
@export var gear_down : float = 0.5

# ObjectTemplate.setGearChangeTime 0.7
@export var gear_change_time : float = 0.7

# ObjectTemplate.newCar2.minRpm / maxRpm
@export var idle_rpm : float = 1000.0
@export var max_rpm : float = 3750.0

# ObjectTemplate.newCar2.brakeTorque / engineBrakeTorque / frictionTorque
@export var brake_torque : float = 2000.0
@export var engine_brake_torque : float = 750.0
@export var friction_torque : float = 100.0

# Calibration constant only - BF2's torque units don't map 1:1 to Godot's
# engine_force units. Tuned against the telemetry CSV (0-90 km/h profile,
# top speed ~88-90 km/h). Re-tune this first if your acceleration curve
# still doesn't match after the other fixes.
@export var engine_force_scale : float = 30.0

# ObjectTemplate.drag 1 - BF2's drag coefficient wasn't actually applied in
# the earlier rewrite (only a small linear_damp was), which is why
# acceleration felt unbounded and the car kept gaining speed well past
# where the telemetry curve flattens out. This is a proper v^2 aerodynamic
# drag force opposing motion, applied in apply_aero_drag().
@export var target_top_speed_kmh : float = 90.0

# If true, aerodynamic_drag_coefficient is auto-calculated at _ready() so
# that drag force balances peak 5th-gear engine force at target_top_speed_kmh.
# Turn this off if you want to hand-tune the coefficient directly instead.
@export var auto_calibrate_drag : bool = true
@export var aerodynamic_drag_coefficient : float = 20.0

# Safety backstop in case the drag model doesn't fully cancel engine force
# at high throttle (e.g. very high engine_force_scale). Cuts drive force
# a small margin above target_top_speed_kmh so speed can't run away
# indefinitely even if the drag curve is under-tuned.
@export var hard_speed_cap_margin : float = 1.1

@export var throttle_response : float = 3.0
@export var steering_angle : float = 0.45

# =====================================================
# SUSPENSION  (ObjectTemplate.setStrength / setDamping, per-wheel Spring template)
# =====================================================

@export_group("Suspension")

# Front (JEP_Paratrooper_Wheel_LF/RF): setStrength 32, setDamping 5
@export var front_suspension_stiffness : float = 32.0

# Rear (JEP_Paratrooper_Wheel_LR/RR): setStrength 28, setDamping 5
@export var rear_suspension_stiffness : float = 28.0

# IMPORTANT FIX: Godot's damping_compression/damping_relaxation are fractions
# of critical damping (0.0-1.0), NOT the raw BF2 setDamping value. Feeding in
# 5.0 directly (as before) is out-of-range and clamped internally - that's
# what was causing the wheels to sink too far and return too slowly.
# These normalized values are a starting point; nudge compression down /
# relaxation up if it still feels floaty, or both up if it feels twitchy.
@export_range(0.0, 1.0) var suspension_damping_compression : float = 0.4
@export_range(0.0, 1.0) var suspension_damping_relaxation : float = 0.55

# How far the wheel can travel from rest position (meters). Too large and
# the wheel visibly sinks into the chassis under load.
@export var suspension_travel : float = 0.22

# Ray length from wheel attachment to ground at rest (meters). Adjust to
# match your JEP_Paratrooper mesh's actual ride height.
@export var wheel_rest_length : float = 0.3

# FIX for RPM/speed mismatch: Godot derives wheel.get_rpm() from the wheel's
# actual rotation using this radius. If it doesn't match your jeep's real
# wheel size, the RPM readout (and therefore your gear-shift points) will
# be wrong relative to true road speed - which is why RPM reads low while
# the car is genuinely moving fast. Measure/estimate your wheel mesh radius
# in meters and set this to match.
@export var wheel_radius : float = 0.35

# =====================================================
# WHEEL GRIP  (ObjectTemplate.grip, per-wheel Spring template)
# =====================================================

@export_group("Wheel Grip")

# Front wheels: grip 4
@export var front_grip : float = 4.0

# Rear wheels: grip 8  (this jeep is RWD, rear tires bite harder)
@export var rear_grip : float = 8.0

# BF2's grip is a small unitless multiplier; Godot's wheel_friction_slip
# wants a larger number (default ~10.4). Scale factor to bring grip into
# a sane Godot range - tune alongside engine_force_scale.
@export var grip_to_friction_scale : float = 3.0

# =====================================================
# WHEEL REFERENCES
# =====================================================

@export_group("Wheel References")

@export var front_left : VehicleWheel3D
@export var front_right : VehicleWheel3D
@export var rear_left : VehicleWheel3D
@export var rear_right : VehicleWheel3D

# =====================================================
# DRIVETRAIN
# =====================================================

@export_group("Drivetrain")

@export var rear_wheel_drive := true
@export var front_wheel_drive := false

# =====================================================
# TELEMETRY LOGGING (matches bf2_telemetry.csv columns exactly)
# timestamp,x,y,z,speed_kmh,gear
# =====================================================

@export_group("Telemetry")

@export var log_telemetry : bool = false
@export var telemetry_path : String = "user://godot_telemetry.csv"
@export var telemetry_interval_msec : int = 62  # matches ~16Hz sample rate in bf2_telemetry.csv

var _telemetry_file : FileAccess
var _telemetry_accum_msec : float = 0.0

# =====================================================
# RUNTIME STATE
# =====================================================

var current_gear := 1
var current_rpm := idle_rpm

var throttle := 0.0
var brake_input := 0.0

var shift_timer := 0.0

# =====================================================
# ENGINE AUDIO - RPM2 "Load" sound
# (ObjectTemplate.activeSafe Sound S_JEP_Paratrooper_Engine_Rpm2)
# Source: objects/vehicles/land/jep_paratrooper/sounds/mono/rpm_load.wav
# base volume 0.62, base pitch 1, decoded from pitchEnvelope/volumeEnvelope
# =====================================================

@export_group("Engine Audio - RPM2 Load")

# Node path to the AudioStreamPlayer3D playing rpm_load.wav
# (matches the $RPM_load reference from the earlier script version).
@export var rpm_load_player_path : NodePath = ^"RPM_load"

# ObjectTemplate.pitch / volume for S_JEP_Paratrooper_Engine_Rpm2
@export var rpm2_base_pitch : float = 1.0
@export var rpm2_base_volume : float = 0.62

# Envelope control points decoded from the tweak file's pitchEnvelope /
# volumeEnvelope strings. Format per point is (x, y) - tangents are all 0
# in the source data so linear interpolation reproduces it exactly.
# x = fraction along the envelope's domain, which we drive from the
# engine's RPM fraction (idle_rpm -> max_rpm mapped to 0.0 -> 1.0).
# y = multiplier applied to base_pitch / base_volume.
const RPM2_PITCH_POINTS : Array = [
	Vector2(0.0, 0.550193),
	Vector2(0.996139, 1.5),
]

const RPM2_VOLUME_POINTS : Array = [
	Vector2(0.003861, 0.0),
	Vector2(0.393822, 0.69112),
	Vector2(0.942085, 1.0),
]

# The Load sound is meant to be heard when the engine is actually under
# load (throttle applied), not just spinning at a given RPM while coasting.
# This blends the Load-sound volume down when off-throttle so it doesn't
# constantly play at full RPM-derived volume while coasting/braking.
@export var rpm2_throttle_influence : bool = true
@export_range(0.0, 1.0) var rpm2_min_throttle_gain : float = 0.15

var _rpm_load_player : AudioStreamPlayer3D

# =====================================================
# READY
# =====================================================

func _ready():
	mass = chassis_mass
	gravity_scale = gravity_modifier
	linear_damp = linear_damp_value
	angular_damp = angular_damp_value

	if override_center_of_mass:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = center_of_mass_override

	setup_suspension()
	setup_drivetrain()
	setup_grip()

	if auto_calibrate_drag:
		_calibrate_drag()

	if has_node(rpm_load_player_path):
		_rpm_load_player = get_node(rpm_load_player_path)
	else:
		push_warning("rpm_load_player_path (%s) not found - RPM2 Load audio will not play." % rpm_load_player_path)

	if print_symmetry_check:
		_run_symmetry_check()

	if log_telemetry:
		_start_telemetry_log()

func _run_symmetry_check():
	print("--- JEP_Paratrooper symmetry check ---")
	if front_left and front_right:
		print("front_left.x = %.4f  front_right.x = %.4f  (should be mirrored)" % [front_left.position.x, front_right.position.x])
		if not is_equal_approx(front_left.position.x, -front_right.position.x):
			push_warning("Front wheels are NOT mirrored on X - likely cause of the lean.")
	if rear_left and rear_right:
		print("rear_left.x = %.4f  rear_right.x = %.4f  (should be mirrored)" % [rear_left.position.x, rear_right.position.x])
		if not is_equal_approx(rear_left.position.x, -rear_right.position.x):
			push_warning("Rear wheels are NOT mirrored on X - likely cause of the lean.")
	print("center_of_mass (effective) = %s" % str(center_of_mass))
	print("---------------------------------------")

func _exit_tree():
	if _telemetry_file:
		_telemetry_file.close()

# =====================================================
# SUSPENSION SETUP
# =====================================================

func setup_suspension():
	for wheel in [front_left, front_right]:
		if wheel == null:
			continue
		wheel.suspension_stiffness = front_suspension_stiffness
		wheel.damping_compression = suspension_damping_compression
		wheel.damping_relaxation = suspension_damping_relaxation
		wheel.suspension_travel = suspension_travel
		wheel.wheel_rest_length = wheel_rest_length
		wheel.wheel_radius = wheel_radius

	for wheel in [rear_left, rear_right]:
		if wheel == null:
			continue
		wheel.suspension_stiffness = rear_suspension_stiffness
		wheel.damping_compression = suspension_damping_compression
		wheel.damping_relaxation = suspension_damping_relaxation
		wheel.suspension_travel = suspension_travel
		wheel.wheel_rest_length = wheel_rest_length
		wheel.wheel_radius = wheel_radius

# =====================================================
# GRIP SETUP
# =====================================================

func setup_grip():
	if front_left:
		front_left.wheel_friction_slip = front_grip * grip_to_friction_scale
	if front_right:
		front_right.wheel_friction_slip = front_grip * grip_to_friction_scale
	if rear_left:
		rear_left.wheel_friction_slip = rear_grip * grip_to_friction_scale
	if rear_right:
		rear_right.wheel_friction_slip = rear_grip * grip_to_friction_scale

# =====================================================
# DRAG CALIBRATION
# =====================================================

# Sets aerodynamic_drag_coefficient so that, at full throttle in top gear,
# drag force balances engine force right around target_top_speed_kmh.
# F_drag = k * v^2, so k = F_engine_top_gear / v_target^2
func _calibrate_drag():
	var top_ratio = gear_ratios[gear_ratios.size() - 1]
	var peak_engine_force = torque * top_ratio * differential * engine_force_scale
	var target_speed_ms = target_top_speed_kmh / 3.6
	if target_speed_ms > 0.0:
		aerodynamic_drag_coefficient = peak_engine_force / (target_speed_ms * target_speed_ms)

# =====================================================
# DRIVETRAIN SETUP
# =====================================================

func setup_drivetrain():
	if front_left:
		front_left.use_as_traction = front_wheel_drive
		front_left.use_as_steering = true
	if front_right:
		front_right.use_as_traction = front_wheel_drive
		front_right.use_as_steering = true
	if rear_left:
		rear_left.use_as_traction = rear_wheel_drive
	if rear_right:
		rear_right.use_as_traction = rear_wheel_drive

# =====================================================
# PHYSICS
# =====================================================

func _physics_process(delta):
	update_input(delta)
	update_rpm(delta)
	update_gearbox(delta)
	apply_engine()
	apply_brakes()
	apply_aero_drag()
	update_engine_audio()
	print(debug_string())

	if log_telemetry:
		_update_telemetry(delta)

# =====================================================
# INPUT
# =====================================================

func update_input(delta):
	var accel = Input.get_action_strength("move_forward")
	var back = Input.get_action_strength("move_backward")

	# Treat "move_backward" as brake while still moving forward, reverse once stopped.
	var target_throttle = accel
	brake_input = 0.0

	if back > 0.0:
		if get_speed_kmh() > 2.0 and _moving_forward():
			brake_input = back
			target_throttle = 0.0
		else:
			target_throttle = -back

	throttle = move_toward(throttle, target_throttle, throttle_response * delta)

	var steer_dir = Input.get_axis("move_right", "move_left")
	steering = steer_dir * steering_angle

func _moving_forward() -> bool:
	var local_vel = global_transform.basis.inverse() * linear_velocity
	var fwd_sign = -1.0 if not mesh_rotated_fix else 1.0
	return sign(local_vel.z) == fwd_sign or is_zero_approx(local_vel.z)

# =====================================================
# RPM  (derived from actual driven-wheel rotation, not just linear speed -
# this tracks wheel spin/slip the same way BF2's newCar2 model does)
# =====================================================

func update_rpm(delta):
	var driven_wheels = []
	if rear_wheel_drive:
		driven_wheels.append(rear_left)
		driven_wheels.append(rear_right)
	if front_wheel_drive:
		driven_wheels.append(front_left)
		driven_wheels.append(front_right)

	var wheel_rpm := 0.0
	var count := 0
	for w in driven_wheels:
		if w:
			wheel_rpm += absf(w.get_rpm())
			count += 1
	if count > 0:
		wheel_rpm /= count

	var ratio = gear_ratios[current_gear - 1]
	var target_rpm = idle_rpm

	if wheel_rpm > 1.0:
		target_rpm = wheel_rpm * ratio * differential
	elif absf(throttle) > 0.05:
		# Standstill rev-up (clutch slip) so the engine still climbs toward
		# redline when throttle is held with wheels not yet turning.
		target_rpm = idle_rpm + (max_rpm - idle_rpm) * absf(throttle)

	target_rpm = clamp(target_rpm, idle_rpm, max_rpm)

	current_rpm = move_toward(current_rpm, target_rpm, 4000.0 * delta)

# =====================================================
# AUTO GEARBOX
# =====================================================

func update_gearbox(delta):
	shift_timer -= delta
	if shift_timer > 0:
		return

	var rpm_percent = current_rpm / max_rpm

	if rpm_percent > gear_up and absf(throttle) > 0.05:
		if current_gear < gear_ratios.size():
			current_gear += 1
			shift_timer = gear_change_time
	elif rpm_percent < gear_down:
		if current_gear > 1:
			current_gear -= 1
			shift_timer = gear_change_time

# =====================================================
# ENGINE
# =====================================================

func apply_engine():
	if brake_input > 0.05:
		engine_force = 0.0
		return

	var ratio = gear_ratios[current_gear - 1]
	var force = torque * ratio * differential * throttle

	var sign_fix = -1.0 if not mesh_rotated_fix else 1.0
	engine_force = sign_fix * force * engine_force_scale

	# Hard safety backstop - cuts drive force once speed exceeds
	# target_top_speed_kmh by hard_speed_cap_margin, in case the drag model
	# doesn't fully balance at very high throttle/torque settings.
	if get_speed_kmh() > target_top_speed_kmh * hard_speed_cap_margin:
		engine_force = 0.0
		return

	# Engine braking / rolling friction when off throttle (BF2 engineBrakeTorque
	# + frictionTorque), replaces the old flat "-speed * 5.0" hack that caused
	# idle-spin jitter from floating point noise near zero speed.
	if absf(throttle) < 0.05:
		var speed_ms = linear_velocity.length()
		if speed_ms > 0.05:
			var coast_decel = (engine_brake_torque + friction_torque) * 0.01
			engine_force = -sign(linear_velocity.dot(-global_transform.basis.z)) * coast_decel * ratio
		else:
			engine_force = 0.0

# =====================================================
# AERODYNAMIC DRAG
# =====================================================

# F = k * v^2, opposing current velocity direction. This is what actually
# limits top speed now - without it, engine_force has nothing pushing back
# and the car accelerates indefinitely regardless of RPM/gear.
func apply_aero_drag():
	var speed_ms = linear_velocity.length()
	if speed_ms < 0.05:
		return
	var drag_force_mag = aerodynamic_drag_coefficient * speed_ms * speed_ms
	var drag_force = -linear_velocity.normalized() * drag_force_mag
	apply_central_force(drag_force)

# =====================================================
# BRAKES
# =====================================================

func apply_brakes():
	if brake_input > 0.05:
		brake = brake_torque * 0.01 * brake_input
	else:
		brake = 0.0

# =====================================================
# ENGINE AUDIO - RPM2 "Load" envelope playback
# =====================================================

func update_engine_audio():
	if not _rpm_load_player:
		return

	var rpm_range = max_rpm - idle_rpm
	var rpm_t = 0.0
	if rpm_range > 0.0:
		rpm_t = clamp((current_rpm - idle_rpm) / rpm_range, 0.0, 1.0)

	var pitch_mult = _evaluate_envelope(RPM2_PITCH_POINTS, rpm_t)
	var volume_mult = _evaluate_envelope(RPM2_VOLUME_POINTS, rpm_t)

	if rpm2_throttle_influence:
		var throttle_gain = max(absf(throttle), rpm2_min_throttle_gain if absf(throttle) > 0.05 else 0.0)
		volume_mult *= throttle_gain

	_rpm_load_player.pitch_scale = rpm2_base_pitch * pitch_mult
	var linear_volume = clamp(rpm2_base_volume * volume_mult, 0.0001, 1.0)
	_rpm_load_player.volume_db = linear_to_db(linear_volume)

# Linear interpolation across a set of (x, y) control points, matching the
# BF2 envelope format (tangents are 0 in every envelope on this vehicle so
# straight lerp reproduces the source curve exactly). Reusable for the
# Idle/Rpm1 envelopes too if you decode those the same way.
func _evaluate_envelope(points: Array, t: float) -> float:
	if points.is_empty():
		return 1.0
	if t <= points[0].x:
		return points[0].y
	if t >= points[-1].x:
		return points[-1].y

	for i in range(points.size() - 1):
		var a : Vector2 = points[i]
		var b : Vector2 = points[i + 1]
		if t >= a.x and t <= b.x:
			var span = b.x - a.x
			var local_t = 0.0 if span <= 0.0 else (t - a.x) / span
			return lerp(a.y, b.y, local_t)

	return points[-1].y

# =====================================================
# TELEMETRY
# =====================================================

func _start_telemetry_log():
	_telemetry_file = FileAccess.open(telemetry_path, FileAccess.WRITE)
	if _telemetry_file:
		_telemetry_file.store_line("timestamp,x,y,z,speed_kmh,gear")
	else:
		push_warning("Could not open telemetry file at %s" % telemetry_path)

func _update_telemetry(delta):
	if not _telemetry_file:
		return
	_telemetry_accum_msec += delta * 1000.0
	if _telemetry_accum_msec < telemetry_interval_msec:
		return
	_telemetry_accum_msec = 0.0

	var t = Time.get_ticks_msec()
	var pos = global_transform.origin
	var line = "%d,%.3f,%.3f,%.3f,%.2f,%d" % [
		t, pos.x, pos.y, pos.z, get_speed_kmh(), current_gear
	]
	_telemetry_file.store_line(line)

# =====================================================
# DEBUG
# =====================================================

func get_speed_kmh():
	return linear_velocity.length() * 3.6

func debug_string():
	var ratio = gear_ratios[current_gear - 1]
	return """
Speed: %.1f km/h
RPM: %.0f
Gear: %d
Ratio: %.2f
Throttle: %.2f
Brake: %.2f
EngineForce: %.0f
""" % [
		get_speed_kmh(),
		current_rpm,
		current_gear,
		ratio,
		throttle,
		brake_input,
		engine_force
	]
