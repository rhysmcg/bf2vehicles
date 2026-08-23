
rem *** Animations ***
animationSystem.createAnimation Objects/Weapons/Stationary/mec_bipod/Animations/3p/3p_mec_bipod_sit.baf
animationManager.looping 0
animationSystem.createAnimation Objects/Weapons/Stationary/mec_bipod/Animations/3p/3p_mec_bipod_stand.baf
animationManager.looping 0
animationSystem.createAnimation Objects/Weapons/Stationary/mec_bipod/Animations/3p/3p_mec_bipod_duck.baf
animationManager.looping 0

rem *** Bundles ***
animationSystem.createBundle lookAround
animationBundle.isLooping 0
animationBundle.playBackward 1
animationBundle.fadeInTime 0.0
animationBundle.fadeOutTime 0.0
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Weapons/Stationary/mec_bipod/Animations/3p/3p_mec_bipod_stand.baf
animationBundle.addAnimation Objects/Weapons/Stationary/mec_bipod/Animations/3p/3p_mec_bipod_sit.baf

animationSystem.createBundle lookAroundDuck
animationBundle.isLooping 1
animationBundle.playBackward 1
animationBundle.fadeInTime 0.2
animationBundle.fadeOutTime 0.2
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Weapons/Stationary/mec_bipod/Animations/3p/3p_mec_bipod_duck.baf

rem *** Triggers ***
animationSystem.createTrigger LookAroundTrigger stand
animationTrigger.addBundle lookAround
animationTrigger.valueHolder 3p_turnRight

animationSystem.createTrigger LookAroundTrigger duck
animationTrigger.addBundle lookAroundDuck
animationTrigger.valueHolder 3p_turnRight

animationSystem.createTrigger PoseTrigger root
animationTrigger.addChild stand
animationTrigger.addChild duck

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root

