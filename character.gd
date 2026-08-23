extends CharacterBody3D

@export var speed = 5.0
@export var jump_velocity = 4.5
@export var acceleration = 8.0
@export var mouse_sensitivity = 0.002 # Added sensitivity export

# Get the gravity from the project settings
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Camera Variables ---
# Reference your pivots here. Make sure these paths match your scene hierarchy!
@onready var horizontal_pivot: Node3D = $Horizontal_Pivot
@onready var vertical_pivot: Node3D = $Horizontal_Pivot/Vertical_Pivot

# Limit the vertical camera angle (in degrees)
var vertical_limit_max_degrees = 60.0
var vertical_limit_min_degrees = -30.0

func _ready():
	# Capture the mouse and hide the cursor when the game starts
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# --- Mouse Input Handling ---
func _unhandled_input(event):
	
	if event.is_action_pressed("ui_cancel"):
		# Toggle mouse mode between captured (hidden) and visible (normal)
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Handle mouse movement input for camera rotation
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		# Rotate the horizontal pivot (around the global Y axis)
		horizontal_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Calculate vertical rotation delta
		var vertical_delta = -event.relative.y * mouse_sensitivity
		
		# Apply vertical rotation with clamping
		var current_vertical_angle = rad_to_deg(vertical_pivot.rotation.x)
		var next_vertical_angle = current_vertical_angle + rad_to_deg(vertical_delta)
		
		# Clamp the angle
		next_vertical_angle = clamp(next_vertical_angle, vertical_limit_min_degrees, vertical_limit_max_degrees)
		
		# Apply the clamped rotation back to the pivot
		vertical_pivot.rotation.x = deg_to_rad(next_vertical_angle)

# --- Physics Process (Movement) ---
func _physics_process(delta):
	# Add the gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Get the input direction
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# Calculate target velocity relative to the CAMERA'S horizontal orientation
	# Instead of using 'transform.basis' of the CharacterBody3D, 
	# we use the 'horizontal_pivot.transform.basis' so the character moves 
	# relative to where the camera is looking horizontally.
	var direction = (horizontal_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		# Accelerate towards the target speed
		velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
	else:
		# Decelerate when no input is given
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)

	move_and_slide()
