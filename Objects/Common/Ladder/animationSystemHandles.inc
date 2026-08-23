
rem *** Animations ***
animationSystem.createAnimation Objects/Common/Ladder/Animations/3p_climbup.baf
animationSystem.createAnimation Objects/Common/Ladder/Animations/3p_climbendofladderhandles.baf
animationSystem.createAnimation Objects/Common/Ladder/Animations/3p_climbdownfast.baf


rem *** Bundles ***
animationSystem.createBundle climb
animationBundle.fadeInTime 0.0
animationBundle.fadeOutTime 0.0
animationBundle.addAnimation Objects/Common/Ladder/Animations/3p_climbup.baf

rem *** Bundles ***
animationSystem.createBundle climbgetoff
animationBundle.fadeInTime 0.0
animationBundle.fadeOutTime 0.0
animationBundle.addAnimation Objects/Common/Ladder/Animations/3p_climbendofladderhandles.baf

animationSystem.createBundle skid
animationBundle.fadeInTime 0.0
animationBundle.fadeOutTime 0.0
animationBundle.addAnimation Objects/Common/Ladder/Animations/3p_climbdownfast.baf

rem *** Triggers ***
animationSystem.createTrigger UpTrigger climbNormal
animationTrigger.addBundle climb
animationTrigger.valueHolder 3p_climb
animationTrigger.useDirection 1

animationSystem.createTrigger UpTrigger climbGetoff
animationTrigger.addBundle climbgetoff
animationTrigger.valueHolder 3p_climb
animationTrigger.useDirection 1

animationSystem.createTrigger MessageTrigger normal_climb
animationTrigger.addChild climbNormal
animationTrigger.message 1

animationSystem.createTrigger MessageTrigger getoff_climb
animationTrigger.addChild climbGetoff
animationTrigger.message 2

animationSystem.createTrigger UpTrigger skid_climb
animationTrigger.addBundle skid
animationTrigger.valueHolder 3p_climb_skid

animationSystem.createTrigger Trigger root
animationTrigger.addChild normal_climb
animationTrigger.addChild getoff_climb
animationTrigger.addChild skid_climb

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root



