animationSystem.cameraSpring.use 1
animationSystem.cameraSpring.amplitude 0.045/0.045/0.045
animationSystem.cameraSpring.zoomDamping 2.9/2.9/0
animationSystem.cameraSpring.stiffness 10/10/10
animationSystem.cameraSpring.move 2/2/2
animationSystem.cameraSpring.look 1/1
animationSystem.cameraSpring.fire 0/0/150

rem *** Animations ***
animationSystem.createAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_deploy.baf
animationManager.looping 0
animationManager.length 0.625
animationSystem.createAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_fire.baf
animationManager.looping 0
animationManager.length 0.458333
animationSystem.createAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_idle1.baf
animationManager.looping 0
animationManager.length 2.95833
animationSystem.createAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_run.baf
animationManager.length 0.666667
animationSystem.createAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_sprint.baf
animationSystem.createAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_stand.baf

rem *** Bundles ***
animationSystem.createBundle deploy
animationBundle.isLooping 0
animationBundle.fadeInTime 0.001
animationBundle.addAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_deploy.baf

animationSystem.createBundle fire
animationBundle.isLooping 0
animationBundle.fadeInTime 0.001
animationBundle.addAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_fire.baf

animationSystem.createBundle idle1
animationBundle.isLooping 0
animationBundle.fadeOutTime 0.3
animationBundle.addAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_idle1.baf

animationSystem.createBundle idle2
animationBundle.isLooping 0
animationBundle.fadeOutTime 0.3

animationSystem.createBundle run
animationBundle.fadeOutTime 0.2
animationBundle.addAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_run.baf

animationSystem.createBundle sprint
animationBundle.fadeOutTime 0.2
animationBundle.addAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_sprint.baf

animationSystem.createBundle still
animationBundle.addAnimation Objects/Weapons/Handheld/C4_Detonator/Animations/1p/1p_detonator_stand.baf


rem *** Triggers ***
animationSystem.createTrigger IdleTrigger idle
animationTrigger.addBundle idle1
animationTrigger.addBundle idle2
animationTrigger.idleTime 30/100

animationSystem.createTrigger Trigger still
animationTrigger.addChild idle
animationTrigger.addBundle still

animationSystem.createTrigger MovementTrigger move
animationTrigger.addBundle run
animationTrigger.valueHolder 1p_move

animationSystem.createTrigger MovementTrigger sprint
animationTrigger.addBundle sprint
animationTrigger.valueHolder 1p_sprint

animationSystem.createTrigger MessageTrigger fire
animationTrigger.addBundle fire
animationTrigger.message 1

animationSystem.createTrigger Trigger normal
animationTrigger.fadeInTime 0.2
animationTrigger.addChild still
animationTrigger.addChild move
animationTrigger.addChild sprint
animationTrigger.addChild fire

animationSystem.createTrigger SwitchMessageTrigger root
animationTrigger.addChild normal
animationTrigger.message 4

animationSystem.createTrigger Trigger startup
animationTrigger.addBundle deploy

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root
animationTrigger.addChild startup

