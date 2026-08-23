
rem *** Animations ***
animationSystem.createAnimation Objects/Vehicles/sea/boat_rib/animations/3p/3p_rib_gunner_stand_360.baf
animationManager.looping 0
animationSystem.createAnimation Objects/Vehicles/sea/boat_rib/animations/3p/3p_rib_gunner_sit_360.baf
animationManager.looping 0

rem *** Bundles ***
animationSystem.createBundle lookAround
animationBundle.isLooping 0
animationBundle.fadeInTime 0
animationBundle.fadeOutTime 0
animationBundle.useSpeedAsTime 1
animationBundle.addAnimation Objects/Vehicles/sea/boat_rib/animations/3p/3p_rib_gunner_stand_360.baf
animationBundle.addAnimation Objects/Vehicles/sea/boat_rib/animations/3p/3p_rib_gunner_sit_360.baf


rem *** Triggers ***
animationSystem.createTrigger LookAroundTrigger root
animationTrigger.addBundle lookAround
animationTrigger.valueHolder 3p_turnRight

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root

