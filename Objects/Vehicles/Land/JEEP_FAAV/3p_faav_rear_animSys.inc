
rem *** Animations ***
animationSystem.createAnimation Objects/Vehicles/Land/JEEP_FAAV/Animations/3p/3p_faav_rearpassenger.baf
animationManager.looping 0
animationManager.length 1.709
animationSystem.createAnimation Objects/Vehicles/Land/JEEP_FAAV/Animations/3p/3p_faav_rearpassenger_die.baf

rem *** Bundles ***
animationSystem.createBundle die
animationBundle.fadeInTime 0.4
animationBundle.fadeOutTime 0
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Vehicles/Land/JEEP_FAAV/Animations/3p/3p_faav_rearpassenger_die.baf

animationSystem.createBundle still
animationBundle.isLooping 0
animationBundle.fadeInTime 0
animationBundle.fadeOutTime 0
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Vehicles/Land/JEEP_FAAV/Animations/3p/3p_faav_rearpassenger.baf


rem *** Triggers ***
animationSystem.createTrigger LookAroundTrigger root
animationTrigger.addBundle still
animationTrigger.valueHolder 3p_turnRight

animationSystem.createTrigger LookAroundTrigger die
animationTrigger.addBundle die

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root
animationTrigger.addChild die

