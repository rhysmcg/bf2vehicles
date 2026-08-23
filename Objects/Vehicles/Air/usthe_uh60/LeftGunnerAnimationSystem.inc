
rem *** Animations ***

animationSystem.createAnimation Objects/Vehicles/Air/USTHE_UH60/Animations/3p/3p_left_minigun_sit.baf
animationManager.looping 0
animationSystem.createAnimation Objects/Vehicles/Air/USTHE_UH60/Animations/3p/3p_left_minigun_stand.baf
animationManager.looping 0
animationSystem.createAnimation Objects/Vehicles/Air/USTHE_UH60/Animations/3p/3p_uh60_minigun_die.baf


rem *** Bundles ***
animationSystem.createBundle lookAround
animationBundle.fadeInTime 0
animationBundle.fadeOutTime 0
animationBundle.isLooping 0
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Vehicles/Air/USTHE_UH60/Animations/3p/3p_left_minigun_stand.baf
animationBundle.addAnimation Objects/Vehicles/Air/USTHE_UH60/Animations/3p/3p_left_minigun_sit.baf

animationSystem.createBundle lookAroundDie
animationBundle.fadeInTime 0.4
animationBundle.fadeOutTime 0
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Vehicles/Air/USTHE_UH60/Animations/3p/3p_uh60_minigun_die.baf

rem *** Triggers ***
animationSystem.createTrigger LookAroundTrigger root
animationTrigger.addBundle lookAround
animationTrigger.valueHolder 3p_turnRight

animationSystem.createTrigger LookAroundTrigger die
animationTrigger.addBundle lookAroundDie

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root
animationTrigger.addChild die

