
rem *** Animations ***
animationSystem.createAnimation Objects/Vehicles/Land/jep_mec_paratrooper/Animations/3p/3p_coDriver_gunner_sit.baf
animationManager.looping 0
animationSystem.createAnimation Objects/Vehicles/Land/jep_mec_paratrooper/Animations/3p/3p_coDriver_gunner_stand.baf
animationManager.looping 0
animationSystem.createAnimation Objects/Vehicles/Land/jep_mec_paratrooper/Animations/3p/3p_coDriver_gunner_die.baf
animationManager.looping 0

rem *** Bundles ***
animationSystem.createBundle die
animationBundle.fadeInTime 0.4
animationBundle.fadeOutTime 0
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Vehicles/Land/jep_mec_paratrooper/Animations/3p/3p_coDriver_gunner_die.baf

animationSystem.createBundle still
animationBundle.isLooping 0
animationBundle.fadeInTime 0
animationBundle.fadeOutTime 0
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Vehicles/Land/jep_mec_paratrooper/Animations/3p/3p_coDriver_gunner_stand.baf
animationBundle.addAnimation Objects/Vehicles/Land/jep_mec_paratrooper/Animations/3p/3p_coDriver_gunner_sit.baf

rem *** Triggers ***
animationSystem.createTrigger LookAroundTrigger root
animationTrigger.addBundle still
animationTrigger.valueHolder 3p_turnRight

animationSystem.createTrigger LookAroundTrigger die
animationTrigger.addBundle die

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root
animationTrigger.addChild die

